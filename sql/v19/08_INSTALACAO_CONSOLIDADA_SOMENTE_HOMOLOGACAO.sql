-- APONTE CIDADÃO V19 — SCRIPT ÚNICO DE HOMOLOGAÇÃO
-- NÃO EXECUTAR NO SUPABASE DE PRODUÇÃO.
-- Executar uma única vez em banco/projeto de homologação SEPARADO.
-- Pré-condições: estrutura V18 instalada, backup verificado, testes planeados.
-- Migrations individuais versionadas em sql/v19/03..07
-- O SCRIPT É TRANSACIONAL: QUALQUER ERRO ANTES DO COMMIT REVERTE TODO O PACOTE.
-- ATENÇÃO: não inclui preenchimento histórico nem alterações de Auth.
-- A V19 só pode ser publicada após testes de leitura/escrita, RLS e perfis.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- ==================== COMPONENTE 1 / 03_rpc_estoque_transacional_NAO_APLICAR.sql ====================
-- APONTE CIDADÃO V19
-- 03/05 — RPCs transacionais de estoque e isolamento de consumo por chamado.
-- RASCUNHO PARA HOMOLOGAÇÃO: não executar na produção V18 sem testes/backup.
-- Depende das tabelas e colunas verificadas na auditoria de 2026-11-03.
-- No frontend V19, v19.js substitui gravações diretas pelas RPCs abaixo.

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

-- PRÓXIMA ETAPA: migrar interface + testar em homologação; só depois aplicar
-- sql/v19/04_rls_estoque_isolamento.sql. NÃO executar migração em V18 sem corte planejado.


-- ==================== COMPONENTE 2 / 04_rls_estoque_isolamento_NAO_APLICAR.sql ====================
-- APONTE CIDADÃO V19 — 04/05
-- Corrige isolamento entre empresas e bloqueia escritas diretas de estoque.
-- EXECUTAR SOMENTE DEPOIS de 03_rpc_estoque_transacional_NAO_APLICAR.sql
-- e dos testes na interface teste-v19/. NÃO aplicar na V18 sem homologação.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Chamados: empresa lê SOMENTE os atribuídos à própria empresa.
DROP POLICY IF EXISTS pol_chamados_sel ON public.chamados;
CREATE POLICY pol_chamados_sel ON public.chamados FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='prefeitura' AND cidade_id=public.minha_cidade()
      AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa()
      AND public.empresa_atende(cidade_id))
  OR (public.meu_perfil()='garantia' AND consorcio_id=public.meu_consorcio()
      AND (status='Aguardando Garantia LED'
        OR (status='Concluído' AND garantia_tipo IS NOT NULL)))
);

DROP POLICY IF EXISTS pol_chamados_upd ON public.chamados;
CREATE POLICY pol_chamados_upd ON public.chamados FOR UPDATE TO authenticated
USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='prefeitura' AND cidade_id=public.minha_cidade())
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa()
      AND public.empresa_atende(cidade_id))
  OR (public.meu_perfil()='garantia' AND consorcio_id=public.meu_consorcio()
      AND (status='Aguardando Garantia LED'
        OR (status='Concluído' AND garantia_tipo IS NOT NULL)))
)
WITH CHECK (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='prefeitura' AND cidade_id=public.minha_cidade())
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa()
      AND public.empresa_atende(cidade_id))
  OR (public.meu_perfil()='garantia' AND consorcio_id=public.meu_consorcio()
      AND (status='Aguardando Garantia LED'
        OR (status='Concluído' AND garantia_tipo IS NOT NULL)))
);
-- Trigger guard_chamados continua responsável por imutabilidade de colunas.
-- O tratamento de conclusão Garantia está na migration 05.

-- Empresas: consórcio administra seu cadastro; executora visualiza só ela.
DROP POLICY IF EXISTS pol_empresas_sel ON public.empresas;
CREATE POLICY pol_empresas_sel ON public.empresas FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='empresa' AND id=public.minha_empresa())
);

DROP POLICY IF EXISTS pol_ec_sel ON public.empresa_cidades;
CREATE POLICY pol_ec_sel ON public.empresa_cidades FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND EXISTS (
    SELECT 1 FROM public.empresas e WHERE e.id=empresa_cidades.empresa_id
      AND e.consorcio_id=public.meu_consorcio()))
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa())
);

DROP POLICY IF EXISTS pol_equipes_sel ON public.equipes;
CREATE POLICY pol_equipes_sel ON public.equipes FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa())
);

-- Usuários: uma executora não consulta usuários de outra empresa.
DROP POLICY IF EXISTS pol_usuarios_sel ON public.usuarios;
CREATE POLICY pol_usuarios_sel ON public.usuarios FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='prefeitura' AND cidade_id=public.minha_cidade())
  OR (public.meu_perfil()='empresa' AND empresa_id=public.minha_empresa())
  OR (public.meu_perfil()='garantia' AND auth_user_id=auth.uid())
);

-- Movimentos do estoque central: empresa lê somente os seus consumos,
-- não vê nomes, datas e materiais lançados em chamados de concorrentes.
DROP POLICY IF EXISTS pol_mov_sel ON public.movimentacoes;
CREATE POLICY pol_mov_sel ON public.movimentacoes FOR SELECT TO authenticated USING (
  public.is_master()
  OR (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  OR (public.meu_perfil()='empresa' AND EXISTS(
    SELECT 1 FROM public.chamados c
    WHERE c.id=movimentacoes.chamado_id
      AND c.empresa_id=public.minha_empresa()
      AND c.consorcio_id=movimentacoes.consorcio_id
  ))
);

-- Auditoria global contém dados transversais. Não compartilhar com Empresa.
DROP POLICY IF EXISTS pol_aud_sel ON public.auditoria;
CREATE POLICY pol_aud_sel ON public.auditoria FOR SELECT TO authenticated USING (
  public.is_master() OR
  (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
);

-- Histórico, materiais de chamados e fotos: acesso sempre subordinado ao chamado.
DROP POLICY IF EXISTS pol_hist_sel ON public.chamado_historico;
CREATE POLICY pol_hist_sel ON public.chamado_historico FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_historico.chamado_id
    AND (
      public.is_master()
      OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
      OR (public.meu_perfil()='prefeitura' AND c.cidade_id=public.minha_cidade())
      OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
      OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
           AND (c.status='Aguardando Garantia LED'
             OR (c.status='Concluído' AND c.garantia_tipo IS NOT NULL)))
    ))
);

DROP POLICY IF EXISTS pol_hist_ins ON public.chamado_historico;
CREATE POLICY pol_hist_ins ON public.chamado_historico FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_historico.chamado_id
    AND (
      public.is_master()
      OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
      OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
      OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
          AND c.garantia_tipo IS NOT NULL)
    ))
);

DROP POLICY IF EXISTS pol_cm_sel ON public.chamado_materiais;
CREATE POLICY pol_cm_sel ON public.chamado_materiais FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_materiais.chamado_id
    AND (
      public.is_master()
      OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
      OR (public.meu_perfil()='prefeitura' AND c.cidade_id=public.minha_cidade())
      OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
      OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
          AND c.garantia_tipo IS NOT NULL)
    ))
);

DROP POLICY IF EXISTS pol_foto_sel ON public.chamado_fotos;
CREATE POLICY pol_foto_sel ON public.chamado_fotos FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_fotos.chamado_id
    AND (
      public.is_master()
      OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
      OR (public.meu_perfil()='prefeitura' AND c.cidade_id=public.minha_cidade())
      OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
      OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
          AND c.garantia_tipo IS NOT NULL)
    ))
);

DROP POLICY IF EXISTS pol_foto_wr ON public.chamado_fotos;
CREATE POLICY pol_foto_wr ON public.chamado_fotos FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_fotos.chamado_id
    AND (
      public.is_master()
      OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
      OR (public.meu_perfil()='prefeitura' AND c.cidade_id=public.minha_cidade())
      OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
      OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
          AND c.garantia_tipo IS NOT NULL)
    ))
);

-- Storage PRIVATE: mesmo controle por chamado atribuído.
CREATE OR REPLACE FUNCTION public._foto_chamado_visivel(p_name text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_parts text[];v_cons uuid;v_cham uuid;
BEGIN
  v_parts:=storage.foldername(p_name);
  IF coalesce(array_length(v_parts,1),0)<>2 THEN RETURN false; END IF;
  BEGIN
    v_cons:=v_parts[1]::uuid;
    v_cham:=v_parts[2]::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
  RETURN EXISTS (
    SELECT 1 FROM public.chamados c
    WHERE c.id=v_cham AND c.consorcio_id=v_cons
      AND (
        public.is_master()
        OR (public.meu_perfil()='consorcio' AND c.consorcio_id=public.meu_consorcio())
        OR (public.meu_perfil()='prefeitura' AND c.cidade_id=public.minha_cidade())
        OR (public.meu_perfil()='empresa' AND c.empresa_id=public.minha_empresa())
        OR (public.meu_perfil()='garantia' AND c.consorcio_id=public.meu_consorcio()
           AND c.garantia_tipo IS NOT NULL)
      )
  );
END;
$$;
REVOKE ALL ON FUNCTION public._foto_chamado_visivel(text) FROM PUBLIC,anon;
-- NOTA: a função é chamada pela policy de storage.objects; conceder a authenticated
-- se o proprietário de storage precisar da permissão explícita.
GRANT EXECUTE ON FUNCTION public._foto_chamado_visivel(text) TO authenticated;

-- Evitar que usuário inativo crie usuários por meio de helper de autorização.
CREATE OR REPLACE FUNCTION public.pode_criar_usuarios_do_logado()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios u
    WHERE u.auth_user_id=auth.uid() AND u.status='ativo'
      AND (u.pode_criar_usuarios=true OR u.perfil='consorcio' OR u.perfil='master')
  );
$$;

-- A trilha de auditoria não pode ser fabricada com INSERT arbitrário pelo navegador.
DROP POLICY IF EXISTS pol_aud_ins ON public.auditoria;
REVOKE INSERT,UPDATE,DELETE ON public.auditoria FROM anon,authenticated;

-- ÚNICA escrita de saldo e de materiais de chamado: RPCs da migração 03.
DROP POLICY IF EXISTS pol_est_wr ON public.estoques;
DROP POLICY IF EXISTS pol_mov_ins ON public.movimentacoes;
DROP POLICY IF EXISTS pol_cm_wr ON public.chamado_materiais;
REVOKE INSERT,UPDATE,DELETE ON
  public.estoques,public.movimentacoes,public.chamado_materiais
  FROM anon,authenticated;
-- Catálogo também vai pela RPC, para registrar variações de saldo.
DROP POLICY IF EXISTS pol_mat_wr ON public.materiais;
REVOKE INSERT,UPDATE,DELETE ON public.materiais FROM anon,authenticated;

-- Consistência adicional: a auditoria anterior mostrou ausência de duplicados
-- por material e consórcio. Rerodar diagnóstico 00 antes deste comando.
CREATE UNIQUE INDEX IF NOT EXISTS v19_estoque_material_consorcio_unico
  ON public.estoques(material_id,consorcio_id)
  WHERE material_id IS NOT NULL AND consorcio_id IS NOT NULL;
ALTER TABLE public.estoques
  ADD CONSTRAINT v19_estoque_saldo_nao_negativo CHECK(
    quantidade_contratada>=0 AND quantidade_disponivel>=0
  ) NOT VALID;

-- Não aplicar na produção até os testes dos perfis e da interface V19 passarem.


-- ==================== COMPONENTE 3 / 05_guard_garantia_e_historico_NAO_APLICAR.sql ====================
-- APONTE CIDADÃO V19 — 05/05
-- Garante conclusão controlada da Garantia LED; demais guards V18 preservados.
-- Base exata: export dos triggers da produção em 2026-11-03.
-- NÃO APLICAR EM PRODUÇÃO sem ambiente de homologação e regressão.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.guard_chamados()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_cidade_cons uuid; v_empresa_cons uuid; v_usuario_cons uuid; v_perfil text;
BEGIN
  IF NEW.consorcio_id IS NULL OR NEW.cidade_id IS NULL THEN RAISE EXCEPTION 'PROIBIDO: chamado sem consorcio/cidade'; END IF;
  SELECT c.consorcio_id INTO v_cidade_cons FROM public.cidades c WHERE c.id=NEW.cidade_id;
  IF v_cidade_cons IS NULL OR v_cidade_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: cidade de outro consorcio'; END IF;
  SELECT c.nome INTO NEW.cidade FROM public.cidades c WHERE c.id=NEW.cidade_id;   -- não confiar no texto do cliente
  IF NEW.empresa_id IS NOT NULL THEN
    SELECT e.consorcio_id, e.nome INTO v_empresa_cons, NEW.empresa FROM public.empresas e WHERE e.id=NEW.empresa_id;
    IF v_empresa_cons IS NULL OR v_empresa_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: empresa de outro consorcio'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.empresa_cidades ec WHERE ec.empresa_id=NEW.empresa_id AND ec.cidade_id=NEW.cidade_id) THEN
      RAISE EXCEPTION 'PROIBIDO: empresa nao atende esta cidade'; END IF;
  ELSE NEW.empresa := NULL; END IF;
  IF NEW.usuario_responsavel_id IS NOT NULL THEN
    SELECT u.consorcio_id INTO v_usuario_cons FROM public.usuarios u WHERE u.id=NEW.usuario_responsavel_id AND u.status='ativo';
    IF v_usuario_cons IS NULL OR v_usuario_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: responsavel de outro consorcio'; END IF;
  END IF;

  IF auth.uid() IS NULL THEN RETURN NEW; END IF;      -- bootstrap/RPC definer (abrir_chamado_publico)
  IF public.is_master() THEN RETURN NEW; END IF;
  v_perfil := public.meu_perfil();

  IF TG_OP='INSERT' THEN
    IF v_perfil='consorcio' THEN
      IF NEW.consorcio_id IS DISTINCT FROM public.meu_consorcio() THEN RAISE EXCEPTION 'PROIBIDO: chamado fora do consorcio'; END IF;
      RETURN NEW;
    END IF;
    IF v_perfil='prefeitura' THEN
      IF NEW.cidade_id IS DISTINCT FROM public.minha_cidade() THEN RAISE EXCEPTION 'PROIBIDO: prefeitura so abre na propria cidade'; END IF;
      IF NEW.empresa_id IS NOT NULL OR NEW.status IS DISTINCT FROM 'Recebido' OR NEW.prioridade IS DISTINCT FROM 'Média'
         OR NEW.sla_horas IS NOT NULL OR COALESCE(NEW.sla_pausado,false) OR NEW.completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PROIBIDO: prefeitura definiu campo administrativo'; END IF;
      RETURN NEW;
    END IF;
    IF v_perfil='empresa' THEN
      IF NEW.empresa_id IS DISTINCT FROM public.minha_empresa() OR NOT public.empresa_atende(NEW.cidade_id) THEN
        RAISE EXCEPTION 'PROIBIDO: empresa fora do proprio escopo'; END IF;
      IF NEW.status IS DISTINCT FROM 'Recebido' OR NEW.prioridade IS DISTINCT FROM 'Média'
         OR NEW.sla_horas IS NOT NULL OR COALESCE(NEW.sla_pausado,false) THEN
        RAISE EXCEPTION 'PROIBIDO: empresa definiu campo administrativo no INSERT'; END IF;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'PROIBIDO: perfil nao pode inserir chamado';
  END IF;

  -- UPDATE: campos estruturais imutáveis p/ não-master
  IF NEW.protocolo IS DISTINCT FROM OLD.protocolo OR NEW.consorcio_id IS DISTINCT FROM OLD.consorcio_id
     OR NEW.origem IS DISTINCT FROM OLD.origem OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'PROIBIDO: tentativa de alterar campo estrutural'; END IF;

  IF v_perfil='consorcio' THEN
    IF NEW.consorcio_id IS DISTINCT FROM public.meu_consorcio() THEN RAISE EXCEPTION 'PROIBIDO: fora do consorcio'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='prefeitura' THEN
    IF OLD.cidade_id IS DISTINCT FROM public.minha_cidade() OR NEW.cidade_id IS DISTINCT FROM OLD.cidade_id THEN
      RAISE EXCEPTION 'PROIBIDO: prefeitura tentou mudar cidade'; END IF;
    IF (to_jsonb(NEW) - ARRAY['bairro','endereco','referencia','area','latitude','longitude','loc_src','tipo','qtd','observacoes','solicitante_nome','solicitante_tel','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['bairro','endereco','referencia','area','latitude','longitude','loc_src','tipo','qtd','observacoes','solicitante_nome','solicitante_tel','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: prefeitura alterou campo administrativo'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='empresa' THEN
    -- V19: atribuição pelo RPC v19_assumir_chamado. O navegador NÃO possui
    -- RLS de UPDATE sobre chamado sem empresa, portanto apenas o RPC pode
    -- realizar esta transição. Campos operacionais permanecem imutáveis.
    IF OLD.empresa_id IS NULL
       AND NEW.empresa_id IS NOT DISTINCT FROM public.minha_empresa()
       AND OLD.status IN ('Recebido','Em programação')
       AND public.empresa_atende(OLD.cidade_id)
       AND (to_jsonb(NEW) - ARRAY['empresa_id','empresa','updated_at']::text[])
         IS NOT DISTINCT FROM
         (to_jsonb(OLD) - ARRAY['empresa_id','empresa','updated_at']::text[]) THEN
      RETURN NEW;
    END IF;
    IF OLD.empresa_id IS DISTINCT FROM public.minha_empresa() OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       OR NEW.cidade_id IS DISTINCT FROM OLD.cidade_id THEN
      RAISE EXCEPTION 'PROIBIDO: empresa tentou mudar atribuicao/cidade'; END IF;
    IF (to_jsonb(NEW) - ARRAY['status','completed_at','observacoes','latitude','longitude','loc_src','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status','completed_at','observacoes','latitude','longitude','loc_src','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: empresa alterou campo fora da execucao'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='garantia' THEN
    -- Garantia atua somente em chamados de garantia de seu consórcio.
    IF OLD.consorcio_id IS DISTINCT FROM public.meu_consorcio()
       OR OLD.status NOT IN ('Aguardando Garantia LED','Concluído')
       OR OLD.garantia_tipo IS NULL THEN
      RAISE EXCEPTION 'PROIBIDO: chamado nao atribuido a Garantia LED';
    END IF;
    IF OLD.status='Concluído' AND NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'PROIBIDO: garantia nao pode reabrir chamado concluido';
    END IF;
    IF OLD.status='Aguardando Garantia LED'
       AND NEW.status NOT IN ('Aguardando Garantia LED','Concluído') THEN
      RAISE EXCEPTION 'PROIBIDO: garantia so pode concluir chamado';
    END IF;
    IF OLD.status='Aguardando Garantia LED' AND NEW.status='Concluído' THEN
      IF NEW.completed_at IS NULL THEN NEW.completed_at:=now(); END IF;
      IF NEW.completed_at < OLD.created_at THEN
        RAISE EXCEPTION 'PROIBIDO: data de conclusao anterior a abertura';
      END IF;
    ELSIF NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
      RAISE EXCEPTION 'PROIBIDO: alterar data de conclusao sem concluir';
    END IF;
    -- Somente status de conclusão, data e metadados de garantia podem mudar.
    IF (to_jsonb(NEW) - ARRAY['status','completed_at','garantia_tipo',
        'garantia_obs','garantia_dt','garantia_user','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status','completed_at','garantia_tipo',
        'garantia_obs','garantia_dt','garantia_user','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: garantia alterou campo operacional';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'PROIBIDO: perfil sem permissao de update';
END $function$;

-- Histórico persistente gerado pelo banco em toda transição de status
-- e em edições de observações. Não depende de localStorage/cliente.
CREATE OR REPLACE FUNCTION public.v19_registrar_historico_chamado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $hist$
DECLARE v_nome text;v_acao text;v_obs text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.observacoes IS NOT DISTINCT FROM OLD.observacoes THEN RETURN NEW; END IF;

  SELECT nome INTO v_nome FROM public.usuarios
    WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  v_nome:=coalesce(v_nome,'Sistema');
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_acao:='Status alterado';
    v_obs:=coalesce(OLD.status,'Sem status')||' → '||coalesce(NEW.status,'Sem status');
  ELSE
    v_acao:='Observações alteradas';
    v_obs:='Alteração de observações do chamado';
  END IF;
  INSERT INTO public.chamado_historico(chamado_id,status,mensagem,observacao,cor,usuario_nome)
   VALUES(NEW.id,NEW.status,v_acao,v_obs,'#1251A3',v_nome);
  RETURN NEW;
END;
$hist$;

DROP TRIGGER IF EXISTS trg_v19_historico_chamados ON public.chamados;
CREATE TRIGGER trg_v19_historico_chamados
  AFTER UPDATE OF status,observacoes ON public.chamados FOR EACH ROW
  EXECUTE FUNCTION public.v19_registrar_historico_chamado();
REVOKE ALL ON FUNCTION public.v19_registrar_historico_chamado() FROM PUBLIC,anon,authenticated;

-- Se a migração 04 foi aplicada, a policy de histórico preserva as permissões
-- de consulta por empresa atribuída. A UI V19 lê o histórico diretamente do banco.


-- ==================== COMPONENTE 4 / 06_portal_configuracoes_NAO_APLICAR.sql ====================
-- APONTE CIDADÃO V19 — 06/06
-- Portal configurável por consórcio + RPCs públicas condicionadas à configuração.
-- NÃO APLICAR EM PRODUÇÃO SEM TESTAR NO AMBIENTE DE HOMOLOGAÇÃO.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE TABLE IF NOT EXISTS public.portal_configuracoes (
  consorcio_id uuid PRIMARY KEY REFERENCES public.consorcios(id) ON DELETE CASCADE,
  portal_ativo boolean NOT NULL DEFAULT true,
  abertura_portal_ativo boolean NOT NULL DEFAULT true,
  consulta_protocolo_ativo boolean NOT NULL DEFAULT true,
  gps_obrigatorio boolean NOT NULL DEFAULT false,
  mostrar_empresa boolean NOT NULL DEFAULT false,
  notificacao_whatsapp boolean NOT NULL DEFAULT false,
  telefone_contato text,
  whatsapp_contato text,
  prazo_medio_texto text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.portal_configuracoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_v19_portal_sel ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_sel ON public.portal_configuracoes
  FOR SELECT TO authenticated USING (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
DROP POLICY IF EXISTS pol_v19_portal_ins ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_ins ON public.portal_configuracoes
  FOR INSERT TO authenticated WITH CHECK (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
DROP POLICY IF EXISTS pol_v19_portal_upd ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_upd ON public.portal_configuracoes
  FOR UPDATE TO authenticated USING (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  ) WITH CHECK (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
REVOKE ALL ON public.portal_configuracoes FROM anon;
GRANT SELECT,INSERT,UPDATE ON public.portal_configuracoes TO authenticated;

-- Consulta anônima estritamente limitada à configuração pública do portal.
CREATE OR REPLACE FUNCTION public.v19_consultar_portal(p_cidade_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT jsonb_build_object(
    'portal_ativo',coalesce(p.portal_ativo,true),
    'abertura_portal_ativo',coalesce(p.abertura_portal_ativo,true),
    'consulta_protocolo_ativo',coalesce(p.consulta_protocolo_ativo,true),
    'gps_obrigatorio',coalesce(p.gps_obrigatorio,false),
    'mostrar_empresa',coalesce(p.mostrar_empresa,false),
    'telefone_contato',p.telefone_contato,
    'whatsapp_contato',p.whatsapp_contato,
    'prazo_medio_texto',p.prazo_medio_texto,
    'consorcio_nome',co.nome
  )
  FROM public.cidades cid JOIN public.consorcios co ON co.id=cid.consorcio_id
  LEFT JOIN public.portal_configuracoes p ON p.consorcio_id=co.id
  WHERE cid.id=p_cidade_id AND cid.status='ativo'
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.v19_consultar_portal(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v19_consultar_portal(uuid) TO anon,authenticated;

-- A abertura pública NÃO pode ignorar as opções desativadas no painel.
-- Contrato original V18 mantido para não quebrar formulários existentes.
CREATE OR REPLACE FUNCTION public.abrir_chamado_publico(
  p_cidade_id uuid,p_tipo text,p_bairro text DEFAULT NULL,p_endereco text DEFAULT NULL,
  p_referencia text DEFAULT NULL,p_area text DEFAULT 'Urbana',p_qtd int DEFAULT 1,
  p_observacoes text DEFAULT NULL,p_solicitante_nome text DEFAULT NULL,p_solicitante_tel text DEFAULT NULL,
  p_latitude numeric DEFAULT NULL,p_longitude numeric DEFAULT NULL,p_loc_src text DEFAULT 'manual')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_cons uuid;v_cidnome text;v_proto text;v_id uuid;v_area text;v_qtd int;
        v_ativo boolean;v_abertura boolean;v_gps boolean;
BEGIN
  IF p_cidade_id IS NULL THEN RAISE EXCEPTION 'CIDADE_OBRIGATORIA'; END IF;
  IF p_tipo IS NULL OR length(btrim(p_tipo))=0 OR length(p_tipo)>200
  THEN RAISE EXCEPTION 'TIPO_OBRIGATORIO'; END IF;
  SELECT cid.consorcio_id,cid.nome,coalesce(port.portal_ativo,true),
         coalesce(port.abertura_portal_ativo,true),coalesce(port.gps_obrigatorio,false)
    INTO v_cons,v_cidnome,v_ativo,v_abertura,v_gps
    FROM public.cidades cid
    JOIN public.consorcios co ON co.id=cid.consorcio_id AND co.status='ativo'
    LEFT JOIN public.portal_configuracoes port ON port.consorcio_id=cid.consorcio_id
    WHERE cid.id=p_cidade_id AND cid.status='ativo';
  IF NOT FOUND THEN RAISE EXCEPTION 'CIDADE_INEXISTENTE'; END IF;
  IF NOT v_ativo OR NOT v_abertura THEN RAISE EXCEPTION 'PORTAL_ABERTURA_DESATIVADA'; END IF;
  IF v_gps AND (p_latitude IS NULL OR p_longitude IS NULL
     OR p_loc_src IS DISTINCT FROM 'gps_mobile') THEN RAISE EXCEPTION 'GPS_OBRIGATORIO'; END IF;
  IF p_latitude IS NOT NULL AND (p_latitude < -90 OR p_latitude>90)
     OR p_longitude IS NOT NULL AND (p_longitude < -180 OR p_longitude>180)
  THEN RAISE EXCEPTION 'GPS_INVALIDO'; END IF;
  v_area:=CASE WHEN p_area='Rural' THEN 'Rural' ELSE 'Urbana' END;
  v_qtd:=greatest(1,least(coalesce(p_qtd,1),999));
  v_proto:=public.gerar_protocolo(p_cidade_id);
  INSERT INTO public.chamados(
    protocolo,consorcio_id,cidade_id,cidade,bairro,endereco,referencia,
    area,tipo,qtd,observacoes,status,prioridade,origem,solicitante_nome,solicitante_tel,
    latitude,longitude,loc_src)
  VALUES(v_proto,v_cons,p_cidade_id,v_cidnome,nullif(btrim(coalesce(p_bairro,'')),''),
    nullif(btrim(coalesce(p_endereco,'')),''),nullif(btrim(coalesce(p_referencia,'')),''),
    v_area,btrim(p_tipo),v_qtd,nullif(btrim(coalesce(p_observacoes,'')),''),
    'Recebido','Média','Público',nullif(btrim(coalesce(p_solicitante_nome,'')),''),
    nullif(btrim(coalesce(p_solicitante_tel,'')),''),p_latitude,p_longitude,
    CASE WHEN p_loc_src IN ('manual','gps_mobile','address_geocoding')
     THEN p_loc_src ELSE 'manual' END) RETURNING id INTO v_id;
  INSERT INTO public.chamado_historico(chamado_id,status,mensagem,cor,usuario_nome)
    VALUES(v_id,'Recebido','Chamado aberto pelo canal público','#1251A3','Portal público');
  RETURN jsonb_build_object('ok',true,'protocolo',v_proto);
END;
$$;
REVOKE ALL ON FUNCTION public.abrir_chamado_publico(uuid,text,text,text,text,text,int,text,text,text,numeric,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.abrir_chamado_publico(uuid,text,text,text,text,text,int,text,text,text,numeric,numeric,text) TO anon,authenticated;

-- Consulta pública por protocolo segue protegida por chave exata
-- e passa a respeitar a permissão de consulta definida por consórcio.
CREATE OR REPLACE FUNCTION public.consultar_protocolo(p_protocolo text)
RETURNS TABLE(protocolo text,cidade text,tipo text,status text,created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT c.protocolo,c.cidade,c.tipo,c.status,c.created_at
    FROM public.chamados c
    LEFT JOIN public.portal_configuracoes pc ON pc.consorcio_id=c.consorcio_id
  WHERE p_protocolo IS NOT NULL AND length(btrim(p_protocolo))>=6
    AND c.protocolo=btrim(p_protocolo)
    AND coalesce(pc.portal_ativo,true)
    AND coalesce(pc.consulta_protocolo_ativo,true)
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.consultar_protocolo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_protocolo(text) TO anon,authenticated;


-- ==================== COMPONENTE 5 / 07_assumir_chamados_NAO_APLICAR.sql ====================
-- APONTE CIDADÃO V19 — 07
-- Chamada disponível: projeção mínima e atribuição concorrente/atômica.
-- Depende da migration 05 (guard_chamados atualizado) e 04 (RLS).
-- NÃO APLICAR EM PRODUÇÃO SEM HOMOLOGAÇÃO.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.v19_listar_disponiveis(p_limite integer DEFAULT 100)
RETURNS TABLE(
  id uuid,protocolo text,cidade text,bairro text,tipo text,qtd integer,
  status text,created_at timestamptz
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_empresa uuid;v_cons uuid;
BEGIN
  SELECT u.empresa_id,e.consorcio_id INTO v_empresa,v_cons
  FROM public.usuarios u JOIN public.empresas e ON e.id=u.empresa_id
  WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa' AND u.status='ativo'
    AND e.status='ativo' LIMIT 1;
  IF v_empresa IS NULL OR v_cons IS NULL THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  RETURN QUERY
    SELECT c.id,c.protocolo,c.cidade,c.bairro,c.tipo,c.qtd,c.status,c.created_at
    FROM public.chamados c
    JOIN public.empresa_cidades ec ON ec.cidade_id=c.cidade_id AND ec.empresa_id=v_empresa
    WHERE c.consorcio_id=v_cons
      AND c.empresa_id IS NULL
      AND c.status IN ('Recebido','Em programação')
    ORDER BY c.created_at ASC,c.id ASC
    LIMIT greatest(1,least(coalesce(p_limite,100),200));
END;
$$;

CREATE OR REPLACE FUNCTION public.v19_assumir_chamado(p_chamado_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user uuid;v_nome text;v_empresa uuid;v_cons uuid;v_empnome text;
        v_chamado uuid;v_protocolo text;
BEGIN
  SELECT u.id,u.nome,u.empresa_id,e.consorcio_id,e.nome
    INTO v_user,v_nome,v_empresa,v_cons,v_empnome
    FROM public.usuarios u JOIN public.empresas e ON e.id=u.empresa_id
    WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa' AND u.status='ativo'
      AND e.status='ativo' LIMIT 1;
  IF v_user IS NULL OR v_empresa IS NULL OR v_cons IS NULL
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  IF p_chamado_id IS NULL THEN RAISE EXCEPTION 'CHAMADO_OBRIGATORIO'; END IF;

  -- UPDATE atômico: só uma transação consegue sair de empresa_id NULL.
  UPDATE public.chamados c
    SET empresa_id=v_empresa,empresa=v_empnome,updated_at=now()
  WHERE c.id=p_chamado_id
    AND c.empresa_id IS NULL
    AND c.consorcio_id=v_cons
    AND c.status IN ('Recebido','Em programação')
    AND EXISTS (
      SELECT 1 FROM public.empresa_cidades ec
        JOIN public.cidades cid ON cid.id=ec.cidade_id
      WHERE ec.empresa_id=v_empresa AND ec.cidade_id=c.cidade_id
        AND cid.consorcio_id=v_cons AND cid.status='ativo'
    )
  RETURNING c.id,c.protocolo INTO v_chamado,v_protocolo;
  IF v_chamado IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_INDISPONIVEL_OU_JA_ATRIBUIDO';
  END IF;

  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,cor,usuario_nome)
  VALUES(v_chamado,'Recebido','Chamado assumido pela empresa',
     'Executor: '||v_empnome,'#1251A3',v_nome);
  RETURN jsonb_build_object('ok',true,'protocolo',v_protocolo,'chamado_id',v_chamado);
END;
$$;
REVOKE ALL ON FUNCTION public.v19_listar_disponiveis(integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_assumir_chamado(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_listar_disponiveis(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_assumir_chamado(uuid) TO authenticated;

COMMIT;
-- Depois: executar diagnóstico de integridade 00 e testes do dossiê V19.
