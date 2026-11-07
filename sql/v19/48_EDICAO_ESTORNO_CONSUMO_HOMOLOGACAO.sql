-- APONTE CIDADAO V19 / SQL 48
-- EDICAO E ESTORNO DE MATERIAIS JA CONSUMIDOS EM CHAMADOS
-- EXECUTAR SOMENTE EM aponte-cidadao-v19-homologacao
-- Nao executar scripts legados "03_rpc_estoque_transacional_NAO_APLICAR".
-- Nao altera dados durante a instalacao. Requer SQLs 35 e 41.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-alfa')
     OR NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-beta')
     OR to_regprocedure('public.consumir_material_chamado(uuid,uuid,numeric)') IS NULL
     OR to_regprocedure('public.v19_movimentar_estoque(uuid,text,numeric,text)') IS NULL
     OR to_regprocedure('public.editar_material_chamado(uuid,numeric)') IS NOT NULL
     OR to_regprocedure('public.remover_material_chamado(uuid)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'SQL48_AMBIENTE_INCORRETO_OU_FUNCOES_JA_INSTALADAS';
  END IF;
END
$guard$;

-- Centraliza a autorizacao que SERA novamente aplicada em cada operacao.
-- A helper nao e executavel por usuarios externos.
CREATE FUNCTION public._v19_ajuste_consumo_autorizado(p_chamado_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $authz$
 SELECT EXISTS (
   SELECT 1
   FROM public.usuarios u
   JOIN public.chamados ch ON ch.id=p_chamado_id
   WHERE u.auth_user_id=auth.uid() AND u.status='ativo'
     AND auth.role()='authenticated'
     AND (
       u.perfil='master'
       OR (u.perfil='consorcio'
           AND u.consorcio_id=ch.consorcio_id)
       OR (u.perfil='empresa'
           AND u.empresa_id IS NOT NULL
           AND u.consorcio_id=ch.consorcio_id
           AND u.empresa_id=ch.empresa_id
           AND EXISTS(
             SELECT 1
             FROM public.empresas e
             JOIN public.empresa_cidades ec ON ec.empresa_id=e.id
             JOIN public.cidades ci ON ci.id=ec.cidade_id
             WHERE e.id=u.empresa_id
               AND e.consorcio_id=ch.consorcio_id
               AND e.status='ativo'
               AND ci.id=ch.cidade_id
               AND ci.consorcio_id=ch.consorcio_id
               AND ci.status='ativo'
           ))
     )
 );
$authz$;
REVOKE ALL ON FUNCTION public._v19_ajuste_consumo_autorizado(uuid)
 FROM PUBLIC,anon,authenticated;

-- Edita a quantidade de um item ja consumido.
-- Delta positivo baixa estoque; delta negativo devolve ao saldo.
-- Congela o preco unitario original da baixa, para nao alterar historico.
CREATE FUNCTION public.editar_material_chamado(
  p_item_id uuid,p_nova_qtd numeric
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=''
AS $editar$
DECLARE
  v_chamado_id uuid;
  v_chamado_consorcio uuid;
  v_chamado_status text;
  v_chamado_protocolo text;
  v_material_id uuid;
  v_material_consorcio uuid;
  v_material_nome text;
  v_qtd_anterior numeric;
  v_preco numeric;
  v_delta numeric;
  v_total numeric;
  v_saldo numeric;
  v_contratado numeric;
  v_saldo_novo numeric;
  v_estoque_id uuid;
  v_user_id uuid;
  v_user_nome text;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;
  IF p_item_id IS NULL OR p_nova_qtd IS NULL OR p_nova_qtd<=0
     OR p_nova_qtd>9999999999
     OR round(p_nova_qtd,2)<>p_nova_qtd THEN
    RAISE EXCEPTION 'QUANTIDADE_INVALIDA' USING ERRCODE='22023';
  END IF;

  SELECT cm.chamado_id INTO v_chamado_id
  FROM public.chamado_materiais cm WHERE cm.id=p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_NAO_DISPONIVEL' USING ERRCODE='42501';
  END IF;

  -- Ordem de bloqueio compativel com SQL 41: chamado -> material -> estoque.
  -- Lock do chamado serializa todos os ajustes relacionados.
  SELECT ch.consorcio_id,ch.status,ch.protocolo
    INTO v_chamado_consorcio,v_chamado_status,v_chamado_protocolo
  FROM public.chamados ch
  WHERE ch.id=v_chamado_id FOR UPDATE;
  IF NOT FOUND OR NOT public._v19_ajuste_consumo_autorizado(v_chamado_id) THEN
    RAISE EXCEPTION 'CHAMADO_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;
  IF v_chamado_status NOT IN (
       'Em programação','Em execução','Aguard. material','Aguardando material'
     ) THEN
    RAISE EXCEPTION 'STATUS_NAO_PERMITE_AJUSTE_DE_CONSUMO' USING ERRCODE='22023';
  END IF;

  -- Pode ter sido removido antes do lock; confira de novo dentro dele.
  SELECT cm.material_id,cm.quantidade,cm.preco_unitario
    INTO v_material_id,v_qtd_anterior,v_preco
  FROM public.chamado_materiais cm
  WHERE cm.id=p_item_id AND cm.chamado_id=v_chamado_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_JA_REMOVIDO' USING ERRCODE='22023';
  END IF;
  IF v_preco IS NULL OR v_preco<0 THEN
    RAISE EXCEPTION 'PRECO_ORIGINAL_INVALIDO' USING ERRCODE='22023';
  END IF;
  v_delta:=p_nova_qtd-v_qtd_anterior;
  IF v_delta=0 THEN
    RAISE EXCEPTION 'QUANTIDADE_NAO_FOI_ALTERADA' USING ERRCODE='22023';
  END IF;

  SELECT m.consorcio_id,m.nome INTO v_material_consorcio,v_material_nome
  FROM public.materiais m
  WHERE m.id=v_material_id FOR UPDATE;
  IF NOT FOUND OR v_material_consorcio IS DISTINCT FROM v_chamado_consorcio THEN
    RAISE EXCEPTION 'MATERIAL_FORA_DO_CONSORCIO' USING ERRCODE='42501';
  END IF;

  SELECT e.id,e.quantidade_disponivel,e.quantidade_contratada
  INTO v_estoque_id,v_saldo,v_contratado
  FROM public.estoques e
  WHERE e.material_id=v_material_id
    AND e.consorcio_id=v_chamado_consorcio
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESTOQUE_NAO_ENCONTRADO' USING ERRCODE='22023';
  END IF;

  v_saldo_novo:=v_saldo-v_delta;
  v_total:=round(v_preco*p_nova_qtd,2);
  IF v_saldo_novo<0 THEN
    RAISE EXCEPTION 'SALDO_INSUFICIENTE' USING ERRCODE='22023';
  END IF;
  IF v_saldo_novo>v_contratado OR v_total>999999999999.99 THEN
    RAISE EXCEPTION 'LIMITE_DE_ESTOQUE_OU_TOTAL' USING ERRCODE='22023';
  END IF;

  SELECT u.id,u.nome INTO v_user_id,v_user_nome
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USUARIO_INATIVO' USING ERRCODE='42501';
  END IF;

  UPDATE public.estoques
  SET quantidade_disponivel=v_saldo_novo,updated_at=clock_timestamp()
  WHERE id=v_estoque_id;

  UPDATE public.chamado_materiais
  SET quantidade=p_nova_qtd,total=v_total
  WHERE id=p_item_id;

  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,chamado_id,tipo,quantidade,
    usuario_id,usuario_nome,origem,observacao
  ) VALUES (
    v_chamado_consorcio,v_material_id,v_chamado_id,
    CASE WHEN v_delta>0 THEN 'consumo' ELSE 'devolucao' END,
    abs(v_delta),v_user_id,v_user_nome,'ajuste_consumo',
    'Item '||p_item_id||': '||v_qtd_anterior||' -> '||p_nova_qtd
  );

  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,usuario_nome
  ) VALUES (
    v_chamado_id,v_chamado_status,'Material consumido ajustado',
    v_material_nome||': '||v_qtd_anterior||' -> '||p_nova_qtd,
    v_user_nome
  );

  RETURN jsonb_build_object(
    'ok',true,'item_id',p_item_id,'protocolo',v_chamado_protocolo,
    'quantidade_anterior',v_qtd_anterior,'quantidade_nova',p_nova_qtd,
    'novo_saldo',v_saldo_novo,'novo_total',v_total
  );
END;
$editar$;

-- Estorna totalmente um item consumido, devolve o saldo e elimina o item
-- da listagem operacional do chamado (historico e movimento permanecem).
CREATE FUNCTION public.remover_material_chamado(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=''
AS $remover$
DECLARE
  v_chamado_id uuid;
  v_consorcio uuid;
  v_status text;
  v_protocolo text;
  v_material uuid;
  v_mat_consorcio uuid;
  v_mat_nome text;
  v_qtd numeric;
  v_estoque_id uuid;
  v_saldo numeric;
  v_contratado numeric;
  v_saldo_novo numeric;
  v_user_id uuid;
  v_user_nome text;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;
  IF p_item_id IS NULL THEN
    RAISE EXCEPTION 'ITEM_OBRIGATORIO' USING ERRCODE='22023';
  END IF;

  SELECT cm.chamado_id INTO v_chamado_id
  FROM public.chamado_materiais cm WHERE cm.id=p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_NAO_DISPONIVEL' USING ERRCODE='42501';
  END IF;

  SELECT ch.consorcio_id,ch.status,ch.protocolo
  INTO v_consorcio,v_status,v_protocolo
  FROM public.chamados ch
  WHERE ch.id=v_chamado_id FOR UPDATE;

  IF NOT FOUND OR NOT public._v19_ajuste_consumo_autorizado(v_chamado_id) THEN
    RAISE EXCEPTION 'CHAMADO_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;

  IF v_status NOT IN (
       'Em programação','Em execução','Aguard. material','Aguardando material'
     ) THEN
    RAISE EXCEPTION 'STATUS_NAO_PERMITE_ESTORNO' USING ERRCODE='22023';
  END IF;

  SELECT cm.material_id,cm.quantidade INTO v_material,v_qtd
  FROM public.chamado_materiais cm
  WHERE cm.id=p_item_id AND cm.chamado_id=v_chamado_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_JA_REMOVIDO' USING ERRCODE='22023';
  END IF;

  SELECT m.consorcio_id,m.nome INTO v_mat_consorcio,v_mat_nome
  FROM public.materiais m WHERE m.id=v_material FOR UPDATE;

  IF NOT FOUND OR v_mat_consorcio IS DISTINCT FROM v_consorcio THEN
    RAISE EXCEPTION 'MATERIAL_FORA_DO_CONSORCIO' USING ERRCODE='42501';
  END IF;

  SELECT e.id,e.quantidade_disponivel,e.quantidade_contratada
    INTO v_estoque_id,v_saldo,v_contratado
  FROM public.estoques e
  WHERE e.material_id=v_material AND e.consorcio_id=v_consorcio
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESTOQUE_NAO_ENCONTRADO' USING ERRCODE='22023';
  END IF;

  v_saldo_novo:=v_saldo+v_qtd;
  IF v_saldo_novo>v_contratado THEN
    RAISE EXCEPTION 'ESTORNO_EXCEDE_ESTOQUE_CONTRATADO'
      USING ERRCODE='22023';
  END IF;

  SELECT u.id,u.nome INTO v_user_id,v_user_nome
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USUARIO_INATIVO' USING ERRCODE='42501';
  END IF;

  UPDATE public.estoques
  SET quantidade_disponivel=v_saldo_novo,updated_at=clock_timestamp()
  WHERE id=v_estoque_id;
  DELETE FROM public.chamado_materiais WHERE id=p_item_id;

  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,chamado_id,tipo,quantidade,
    usuario_id,usuario_nome,origem,observacao
  ) VALUES (
    v_consorcio,v_material,v_chamado_id,
    'estorno',v_qtd,v_user_id,v_user_nome,
    'estorno_consumo',
    'Estorno integral do item '||p_item_id
  );

  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,usuario_nome
  ) VALUES (
    v_chamado_id,v_status,'Material consumido estornado',
    v_mat_nome||' x '||v_qtd||' (item '||p_item_id||')',
    v_user_nome
  );

  RETURN jsonb_build_object(
    'ok',true,'item_id',p_item_id,
    'protocolo',v_protocolo,'quantidade_estornada',v_qtd,
    'novo_saldo',v_saldo_novo
  );
END;
$remover$;

REVOKE ALL ON FUNCTION public.editar_material_chamado(uuid,numeric)
 FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.remover_material_chamado(uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.editar_material_chamado(uuid,numeric)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_material_chamado(uuid)
 TO authenticated;

-- Nenhum dos perfis pode editar as tabelas diretamente.
REVOKE INSERT,UPDATE,DELETE ON
 public.chamado_materiais,public.estoques,
 public.movimentacoes,public.chamado_historico
FROM anon,authenticated;

COMMIT;

SELECT 'RPC edicao instalada' AS verificacao,
  CASE WHEN to_regprocedure('public.editar_material_chamado(uuid,numeric)')
      IS NOT NULL THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'RPC estorno instalada',
  CASE WHEN to_regprocedure('public.remover_material_chamado(uuid)')
      IS NOT NULL THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs permitidas a authenticated',
  CASE WHEN has_function_privilege(
          'authenticated','public.editar_material_chamado(uuid,numeric)','EXECUTE')
        AND has_function_privilege(
          'authenticated','public.remover_material_chamado(uuid)','EXECUTE')
      THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs bloqueadas para anon',
  CASE WHEN NOT has_function_privilege(
          'anon','public.editar_material_chamado(uuid,numeric)','EXECUTE')
        AND NOT has_function_privilege(
          'anon','public.remover_material_chamado(uuid)','EXECUTE')
      THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Escrita direta de consumo bloqueada',
  CASE WHEN NOT has_table_privilege(
          'authenticated','public.chamado_materiais','UPDATE')
        AND NOT has_table_privilege(
          'authenticated','public.chamado_materiais','DELETE')
        AND NOT has_table_privilege(
          'authenticated','public.estoques','UPDATE')
      THEN 'OK' ELSE 'FALHA' END;
