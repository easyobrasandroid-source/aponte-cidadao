-- APONTE CIDADÃO V19
-- 03/05 — RPCs transacionais de estoque e isolamento de consumo por chamado.
-- RASCUNHO PARA HOMOLOGAÇÃO: não executar na produção V18 sem testes/backup.
-- Depende das tabelas e colunas verificadas na auditoria de 2026-11-03.
-- No frontend V19, v19.js substitui gravações diretas pelas RPCs abaixo.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- A autorização nunca depende de consorcio_id enviado pelo navegador.
CREATE OR REPLACE FUNCTION public._v19_pode_gerenciar_estoque(p_consorcio uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.usuarios u
    WHERE u.auth_user_id = auth.uid()
      AND u.status='ativo'
      AND (u.perfil='master'
        OR (u.perfil='consorcio' AND u.consorcio_id=p_consorcio))
  );
$$;

-- Empresas executoras só operam o chamado quando forem sua empresa ATRIBUÍDA.
-- Atendimento à cidade por si só nunca é suficiente.
CREATE OR REPLACE FUNCTION public._v19_pode_consumir_no_chamado(p_chamado uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS(
    SELECT 1
    FROM public.usuarios u
    JOIN public.chamados ch ON ch.id=p_chamado
    WHERE u.auth_user_id=auth.uid() AND u.status='ativo'
      AND (
        u.perfil='master'
        OR (u.perfil='consorcio' AND ch.consorcio_id=u.consorcio_id)
        OR (u.perfil='empresa' AND ch.empresa_id=u.empresa_id
          AND EXISTS(
            SELECT 1
            FROM public.empresas emp
            JOIN public.empresa_cidades ec ON ec.empresa_id=emp.id
            JOIN public.cidades cid ON cid.id=ec.cidade_id
            WHERE emp.id=u.empresa_id
              AND emp.status='ativo'
              AND emp.consorcio_id=ch.consorcio_id
              AND ec.cidade_id=ch.cidade_id
              AND cid.consorcio_id=ch.consorcio_id
          ))
      )
  );
$$;

-- Cadastro/edição atômicos do catálogo + saldo. Qualquer diferença de saldo
-- gera movimentação "ajuste". Não há atualização silenciosa de quantidade.
CREATE OR REPLACE FUNCTION public.v19_salvar_material(
  p_material_id uuid,
  p_consorcio_id uuid,
  p_nome text,
  p_unidade text,
  p_estoque_minimo numeric,
  p_preco_unitario numeric,
  p_quantidade_contratada numeric,
  p_quantidade_disponivel numeric
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid uuid; v_nome text; v_id uuid; v_cons_existente uuid;
  v_estoque_id uuid; v_saldo_antigo numeric; v_cont_antigo numeric;
  v_variacao numeric; v_criado boolean := false;
BEGIN
  SELECT id,nome INTO v_uid,v_nome FROM public.usuarios
  WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF v_uid IS NULL OR NOT COALESCE(public._v19_pode_gerenciar_estoque(p_consorcio_id),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;

  IF p_consorcio_id IS NULL OR NOT EXISTS(
     SELECT 1 FROM public.consorcios c WHERE c.id=p_consorcio_id)
  THEN RAISE EXCEPTION 'CONSORCIO_INVALIDO'; END IF;
  IF p_nome IS NULL OR btrim(p_nome)='' OR length(p_nome)>250
  THEN RAISE EXCEPTION 'NOME_INVALIDO'; END IF;
  IF p_quantidade_contratada IS NULL OR p_quantidade_disponivel IS NULL
     OR p_quantidade_contratada<0 OR p_quantidade_disponivel<0
     OR p_quantidade_disponivel>p_quantidade_contratada
     OR p_quantidade_contratada>9999999999 OR p_quantidade_disponivel>9999999999
     OR round(p_quantidade_contratada,2)<>p_quantidade_contratada
     OR round(p_quantidade_disponivel,2)<>p_quantidade_disponivel
  THEN RAISE EXCEPTION 'QUANTIDADE_INVALIDA'; END IF;
  IF p_estoque_minimo IS NULL OR p_estoque_minimo<0
     OR p_preco_unitario IS NULL OR p_preco_unitario<0
     OR p_preco_unitario>9999999999
  THEN RAISE EXCEPTION 'VALORES_INVALIDOS'; END IF;

  IF p_material_id IS NOT NULL THEN
    SELECT consorcio_id INTO v_cons_existente
      FROM public.materiais WHERE id=p_material_id FOR UPDATE;
    IF NOT FOUND OR v_cons_existente IS DISTINCT FROM p_consorcio_id
    THEN RAISE EXCEPTION 'MATERIAL_NAO_PERTENCE_AO_CONSORCIO'; END IF;
    UPDATE public.materiais
      SET nome=btrim(p_nome), unidade=coalesce(nullif(btrim(p_unidade),''),'Un.'),
          estoque_minimo=p_estoque_minimo, preco_unitario=p_preco_unitario
      WHERE id=p_material_id;
    v_id:=p_material_id;
  ELSE
    INSERT INTO public.materiais(
       consorcio_id,nome,unidade,estoque_minimo,preco_unitario,status)
    VALUES(
       p_consorcio_id,btrim(p_nome),coalesce(nullif(btrim(p_unidade),''),'Un.'),
       p_estoque_minimo,p_preco_unitario,'ativo')
    RETURNING id INTO v_id;
    v_criado:=true;
  END IF;

  SELECT id,quantidade_disponivel,quantidade_contratada
    INTO v_estoque_id,v_saldo_antigo,v_cont_antigo
    FROM public.estoques
    WHERE material_id=v_id AND consorcio_id=p_consorcio_id FOR UPDATE;

  IF FOUND THEN
    UPDATE public.estoques
      SET quantidade_contratada=p_quantidade_contratada,
          quantidade_disponivel=p_quantidade_disponivel, updated_at=now()
      WHERE id=v_estoque_id;
    v_variacao:=p_quantidade_disponivel-v_saldo_antigo;
  ELSE
    IF EXISTS(SELECT 1 FROM public.estoques WHERE material_id=v_id)
    THEN RAISE EXCEPTION 'ESTOQUE_DE_OUTRO_CONSORCIO'; END IF;
    INSERT INTO public.estoques(
        material_id,consorcio_id,quantidade_contratada,quantidade_disponivel)
      VALUES(v_id,p_consorcio_id,p_quantidade_contratada,p_quantidade_disponivel);
    v_variacao:=p_quantidade_disponivel;
  END IF;

  IF v_variacao<>0 OR (NOT v_criado AND v_cont_antigo IS DISTINCT FROM p_quantidade_contratada) THEN
    INSERT INTO public.movimentacoes(
      consorcio_id,material_id,tipo,quantidade,usuario_id,usuario_nome,observacao)
    VALUES(p_consorcio_id,v_id,'ajuste',abs(v_variacao),v_uid,v_nome,
      'V19: ajuste cadastral; saldo anterior '||coalesce(v_saldo_antigo,0)||
      ', novo '||p_quantidade_disponivel||
      '; contratado anterior '||coalesce(v_cont_antigo,0)||
      ', novo '||p_quantidade_contratada);
  END IF;
  RETURN jsonb_build_object('ok',true,'material_id',v_id,'saldo',p_quantidade_disponivel);
END;
$$;

-- Entrada/saída manuais atômicas, com trilha de auditoria completa.
CREATE OR REPLACE FUNCTION public.v19_movimentar_estoque(
  p_material_id uuid,p_tipo text,p_quantidade numeric,p_observacao text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_estoque uuid; v_cons uuid; v_saldo numeric; v_contratado numeric;
  v_uid uuid; v_nome text; v_novo numeric; v_novo_contratado numeric;
BEGIN
  IF p_tipo NOT IN ('entrada','saida') OR p_quantidade IS NULL
     OR p_quantidade<=0 OR p_quantidade>9999999999
     OR round(p_quantidade,2)<>p_quantidade
  THEN RAISE EXCEPTION 'MOVIMENTACAO_INVALIDA'; END IF;

  SELECT id,nome INTO v_uid,v_nome FROM public.usuarios
    WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  SELECT e.id,e.consorcio_id,e.quantidade_disponivel,e.quantidade_contratada
    INTO v_estoque,v_cons,v_saldo,v_contratado
    FROM public.estoques e WHERE e.material_id=p_material_id FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'ESTOQUE_NAO_ENCONTRADO'; END IF;
  IF v_uid IS NULL OR NOT COALESCE(public._v19_pode_gerenciar_estoque(v_cons),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  IF p_tipo='saida' AND v_saldo<p_quantidade
  THEN RAISE EXCEPTION 'SALDO_INSUFICIENTE'; END IF;

  v_novo:=v_saldo+CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE -p_quantidade END;
  v_novo_contratado:=v_contratado+CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE 0 END;

  UPDATE public.estoques
    SET quantidade_disponivel=v_novo,quantidade_contratada=v_novo_contratado,updated_at=now()
    WHERE id=v_estoque;

  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,tipo,quantidade,usuario_nome,usuario_id,observacao)
  VALUES(v_cons,p_material_id,p_tipo,p_quantidade,v_nome,v_uid,left(p_observacao,500));

  RETURN jsonb_build_object('ok',true,'novo_saldo',v_novo,'contratado',v_novo_contratado);
END;
$$;

CREATE OR REPLACE FUNCTION public.v19_excluir_material(p_material_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_cons uuid; v_qtd int; BEGIN
  SELECT consorcio_id INTO v_cons FROM public.materiais WHERE id=p_material_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MATERIAL_NAO_ENCONTRADO'; END IF;
  IF NOT COALESCE(public._v19_pode_gerenciar_estoque(v_cons),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  IF EXISTS(SELECT 1 FROM public.chamado_materiais WHERE material_id=p_material_id)
     OR EXISTS(SELECT 1 FROM public.movimentacoes WHERE material_id=p_material_id)
  THEN RAISE EXCEPTION 'MATERIAL_COM_HISTORICO_NAO_PODE_SER_EXCLUIDO'; END IF;
  DELETE FROM public.estoques WHERE material_id=p_material_id;
  DELETE FROM public.materiais WHERE id=p_material_id;
  GET DIAGNOSTICS v_qtd=ROW_COUNT;
  IF v_qtd<>1 THEN RAISE EXCEPTION 'EXCLUSAO_NAO_CONFIRMADA'; END IF;
  RETURN jsonb_build_object('ok',true,'excluido',p_material_id);
END;
$$;

-- Substitui as três RPCs V18 pelo mesmo contrato PostgREST, mas com autorização
-- vinculada ao ID do chamado em vez da cidade atendida.
CREATE OR REPLACE FUNCTION public.consumir_material_chamado(
  p_chamado_id uuid,p_material_id uuid,p_quantidade numeric
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_cons uuid; v_cid uuid; v_uid uuid; v_nome text; v_nome_mat text;
        v_preco numeric; v_saldo numeric; v_eid uuid; v_total numeric;
BEGIN
  SELECT id,nome INTO v_uid,v_nome FROM public.usuarios
  WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NAO_AUTENTICADO'; END IF;
  IF p_quantidade IS NULL OR p_quantidade<=0
     OR round(p_quantidade,2)<>p_quantidade
  THEN RAISE EXCEPTION 'QUANTIDADE_INVALIDA'; END IF;

  SELECT consorcio_id,cidade_id INTO v_cons,v_cid FROM public.chamados WHERE id=p_chamado_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CHAMADO_INEXISTENTE'; END IF;
  IF NOT COALESCE(public._v19_pode_consumir_no_chamado(p_chamado_id),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;

  SELECT nome,preco_unitario INTO v_nome_mat,v_preco FROM public.materiais
    WHERE id=p_material_id AND consorcio_id=v_cons AND status='ativo';
  IF NOT FOUND THEN RAISE EXCEPTION 'MATERIAL_FORA_DO_CONSORCIO'; END IF;
  SELECT id,quantidade_disponivel INTO v_eid,v_saldo FROM public.estoques
    WHERE material_id=p_material_id AND consorcio_id=v_cons FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SEM_ESTOQUE'; END IF;
  IF v_saldo<p_quantidade THEN RAISE EXCEPTION 'SALDO_INSUFICIENTE'; END IF;

  v_total:=p_quantidade*coalesce(v_preco,0);
  UPDATE public.estoques SET quantidade_disponivel=quantidade_disponivel-p_quantidade,
    updated_at=now() WHERE id=v_eid;
  INSERT INTO public.chamado_materiais(
    chamado_id,material_id,quantidade,preco_unitario,total,usuario_nome)
    VALUES(p_chamado_id,p_material_id,p_quantidade,v_preco,v_total,v_nome);
  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,tipo,quantidade,chamado_id,usuario_nome,usuario_id)
    VALUES(v_cons,p_material_id,'consumo',p_quantidade,p_chamado_id,v_nome,v_uid);
  INSERT INTO public.chamado_historico(
    chamado_id,mensagem,observacao,cor,usuario_nome)
    VALUES(p_chamado_id,'Material consumido',v_nome_mat||' x '||p_quantidade,'#6D28D9',v_nome);

  RETURN jsonb_build_object('ok',true,'novo_saldo',v_saldo-p_quantidade,'total',v_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.editar_material_chamado(
  p_item_id uuid,p_nova_qtd numeric
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_cham uuid;v_mat uuid;v_oldq numeric;v_preco numeric;v_cons uuid;
        v_uid uuid;v_nome text;v_eid uuid;v_saldo numeric;v_diff numeric;
BEGIN
  SELECT id,nome INTO v_uid,v_nome FROM public.usuarios
    WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NAO_AUTENTICADO'; END IF;
  IF p_nova_qtd IS NULL OR p_nova_qtd<=0 OR round(p_nova_qtd,2)<>p_nova_qtd
  THEN RAISE EXCEPTION 'QUANTIDADE_INVALIDA'; END IF;
  SELECT chamado_id,material_id,quantidade,preco_unitario
    INTO v_cham,v_mat,v_oldq,v_preco FROM public.chamado_materiais
    WHERE id=p_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ITEM_NAO_ENCONTRADO'; END IF;
  IF NOT COALESCE(public._v19_pode_consumir_no_chamado(v_cham),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  SELECT consorcio_id INTO v_cons FROM public.chamados WHERE id=v_cham;
  SELECT id,quantidade_disponivel INTO v_eid,v_saldo
    FROM public.estoques WHERE material_id=v_mat AND consorcio_id=v_cons FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SEM_ESTOQUE'; END IF;
  v_diff:=p_nova_qtd-v_oldq;
  IF v_diff=0 THEN RETURN jsonb_build_object('ok',true,'sem_alteracao',true,'novo_saldo',v_saldo); END IF;
  IF v_diff>0 AND v_saldo<v_diff THEN RAISE EXCEPTION 'SALDO_INSUFICIENTE'; END IF;

  UPDATE public.estoques SET quantidade_disponivel=quantidade_disponivel-v_diff,
    updated_at=now() WHERE id=v_eid;
  UPDATE public.chamado_materiais SET quantidade=p_nova_qtd,
    total=p_nova_qtd*coalesce(v_preco,0) WHERE id=p_item_id;
  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,tipo,quantidade,chamado_id,usuario_nome,usuario_id)
    VALUES(v_cons,v_mat,CASE WHEN v_diff>0 THEN 'consumo' ELSE 'devolucao' END,
       abs(v_diff),v_cham,v_nome,v_uid);
  INSERT INTO public.chamado_historico(chamado_id,mensagem,observacao,usuario_nome,cor)
    VALUES(v_cham,'Material ajustado',v_oldq||' → '||p_nova_qtd,v_nome,'#6D28D9');
  RETURN jsonb_build_object('ok',true,'novo_saldo',v_saldo-v_diff);
END;
$$;

CREATE OR REPLACE FUNCTION public.remover_material_chamado(p_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_cham uuid;v_mat uuid;v_qtd numeric;v_cons uuid;
        v_uid uuid;v_nome text;v_eid uuid;v_saldo numeric;
BEGIN
  SELECT id,nome INTO v_uid,v_nome FROM public.usuarios
    WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NAO_AUTENTICADO'; END IF;
  SELECT chamado_id,material_id,quantidade
    INTO v_cham,v_mat,v_qtd FROM public.chamado_materiais
    WHERE id=p_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ITEM_NAO_ENCONTRADO'; END IF;
  IF NOT COALESCE(public._v19_pode_consumir_no_chamado(v_cham),false)
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  SELECT consorcio_id INTO v_cons FROM public.chamados WHERE id=v_cham;
  SELECT id,quantidade_disponivel INTO v_eid,v_saldo FROM public.estoques
    WHERE material_id=v_mat AND consorcio_id=v_cons FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SEM_ESTOQUE'; END IF;
  UPDATE public.estoques SET quantidade_disponivel=quantidade_disponivel+v_qtd,
    updated_at=now() WHERE id=v_eid;
  DELETE FROM public.chamado_materiais WHERE id=p_item_id;
  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,tipo,quantidade,chamado_id,usuario_nome,usuario_id)
    VALUES(v_cons,v_mat,'estorno',v_qtd,v_cham,v_nome,v_uid);
  INSERT INTO public.chamado_historico(chamado_id,mensagem,observacao,usuario_nome,cor)
    VALUES(v_cham,'Material removido (estorno)','Qtd devolvida: '||v_qtd,
      v_nome,'#6D28D9');
  RETURN jsonb_build_object('ok',true,'novo_saldo',v_saldo+v_qtd,'estornado',v_qtd);
END;
$$;

-- A enumeração de RPCs pode ser pública, mas a execução é restrita ao authenticated
-- e cada função valida identidade/perfil/escopo antes de ler ou alterar registros.
REVOKE ALL ON FUNCTION public._v19_pode_gerenciar_estoque(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public._v19_pode_consumir_no_chamado(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_movimentar_estoque(uuid,text,numeric,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_excluir_material(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.consumir_material_chamado(uuid,uuid,numeric) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.editar_material_chamado(uuid,numeric) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.remover_material_chamado(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_movimentar_estoque(uuid,text,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_excluir_material(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consumir_material_chamado(uuid,uuid,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.editar_material_chamado(uuid,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_material_chamado(uuid) TO authenticated;

COMMIT;

-- PRÓXIMA ETAPA: migrar interface + testar em homologação; só depois aplicar
-- sql/v19/04_rls_estoque_isolamento.sql. NÃO executar migração em V18 sem corte planejado.
