-- APONTE CIDADAO V19 / SQL 28
-- FLUXO BASICO DE STATUS DE CHAMADOS COMUNS
-- SOMENTE NO PROJETO aponte-cidadao-v19-homologacao
-- Nao mexe no chamado de garantia e nao concede UPDATE direto.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $check$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-alfa')
     OR NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-beta')
     OR to_regprocedure('public.v19_assumir_chamado(uuid)') IS NULL
     OR to_regprocedure('public.v19_concluir_garantia(uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger
       WHERE tgrelid='public.chamados'::regclass
         AND tgname='trg_v19_historico_chamados' AND NOT tgisinternal)
  THEN
    RAISE EXCEPTION 'V19_HOMOLOGACAO_OU_PRE_REQUISITOS_AUSENTES';
  END IF;
END
$check$;

-- API recebe apenas UUID de chamado + status proposto.
-- O servidor obtém permissões exclusivamente da conta Supabase Auth.
CREATE OR REPLACE FUNCTION public.v19_atualizar_status_chamado(
  p_chamado_id uuid,
  p_novo_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $status$
DECLARE
  v_perfil text;
  v_consorcio uuid;
  v_empresa uuid;
  v_status_anterior text;
  v_protocolo text;
  v_consorcio_chamado uuid;
  v_empresa_chamado uuid;
  v_cidade_chamado uuid;
  v_status_normalizado text := btrim(coalesce(p_novo_status,''));
  v_data_abertura timestamptz;
  v_data_conclusao timestamptz;
  v_status_conclusao timestamptz;
  v_garantia_tipo text;
  v_agora timestamptz;
  v_allowed boolean := false;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  IF p_chamado_id IS NULL
     OR v_status_normalizado NOT IN (
       'Recebido','Em programação','Em execução',
       'Aguard. material','Concluído'
     ) THEN
    RAISE EXCEPTION 'CHAMADO_OU_STATUS_INVALIDO' USING ERRCODE='22023';
  END IF;

  SELECT u.perfil,u.consorcio_id,u.empresa_id
    INTO v_perfil,v_consorcio,v_empresa
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';

  IF NOT FOUND OR v_perfil NOT IN ('master','consorcio','empresa') THEN
    RAISE EXCEPTION 'PERFIL_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;

  -- Registro bloqueado durante checagem + mudança para evitar race.
  SELECT c.status,c.protocolo,c.consorcio_id,c.empresa_id,c.cidade_id,
         c.created_at,c.completed_at,c.garantia_tipo
    INTO v_status_anterior,v_protocolo,v_consorcio_chamado,
         v_empresa_chamado,v_cidade_chamado,
         v_data_abertura,v_status_conclusao,v_garantia_tipo
  FROM public.chamados c
  WHERE c.id=p_chamado_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHAMADO_NAO_ENCONTRADO' USING ERRCODE='42501';
  END IF;

  IF v_perfil='master' THEN
    NULL; -- master pode atuar em qualquer consorcio; somente status comum.
  ELSIF v_perfil='consorcio' THEN
    IF v_consorcio IS DISTINCT FROM v_consorcio_chamado THEN
      RAISE EXCEPTION 'CHAMADO_DE_OUTRO_CONSORCIO' USING ERRCODE='42501';
    END IF;
  ELSE
    IF v_consorcio IS DISTINCT FROM v_consorcio_chamado
       OR v_empresa IS NULL
       OR v_empresa IS DISTINCT FROM v_empresa_chamado
       OR NOT EXISTS (
         SELECT 1 FROM public.empresas e
         JOIN public.empresa_cidades ec ON ec.empresa_id=e.id
         JOIN public.cidades cid ON cid.id=ec.cidade_id
         WHERE e.id=v_empresa
           AND e.consorcio_id=v_consorcio
           AND e.status='ativo'
           AND cid.id=v_cidade_chamado
           AND cid.consorcio_id=v_consorcio
           AND cid.status='ativo'
       ) THEN
      RAISE EXCEPTION 'EMPRESA_NAO_AUTORIZADA_AO_CHAMADO'
        USING ERRCODE='42501';
    END IF;
  END IF;

  -- O fluxo de Garantia LED ja tem sua RPC exclusiva dos SQLs 17/18.
  -- Nenhum status concluido pode ser reaberto acidentalmente.
  IF v_status_anterior IN ('Concluído','Aguardando Garantia LED')
     OR v_status_conclusao IS NOT NULL
     OR nullif(btrim(coalesce(v_garantia_tipo,'')),'') IS NOT NULL THEN
    RAISE EXCEPTION 'CHAMADO_USA_FLUXO_DE_GARANTIA_OU_JA_CONCLUIDO'
      USING ERRCODE='22023';
  END IF;

  -- Transicoes controladas (sem saltar para "Recebido" desde a execucao).
  v_allowed := CASE v_status_anterior
    WHEN 'Novo' THEN v_status_normalizado IN ('Recebido','Em programação')
    WHEN 'Recebido' THEN v_status_normalizado IN
      ('Em programação','Em execução','Aguard. material','Concluído')
    WHEN 'Em programação' THEN v_status_normalizado IN
      ('Em execução','Aguard. material','Concluído')
    WHEN 'Em execução' THEN v_status_normalizado IN
      ('Aguard. material','Concluído')
    WHEN 'Aguard. material' THEN v_status_normalizado IN
      ('Em execução','Concluído')
    WHEN 'Aguardando material' THEN v_status_normalizado IN
      ('Em execução','Concluído')
    WHEN 'Em atraso' THEN v_status_normalizado IN
      ('Em execução','Concluído')
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'TRANSICAO_DE_STATUS_NAO_PERMITIDA'
      USING ERRCODE='22023';
  END IF;

  v_agora := clock_timestamp();
  IF v_agora < v_data_abertura THEN
    RAISE EXCEPTION 'DATA_DE_ATUALIZACAO_INVALIDA' USING ERRCODE='22023';
  END IF;

  v_data_conclusao := CASE WHEN v_status_normalizado='Concluído'
      THEN v_agora ELSE NULL END;

  UPDATE public.chamados
  SET status=v_status_normalizado,
      completed_at=v_data_conclusao,
      updated_at=v_agora
  WHERE id=p_chamado_id
    AND status IS NOT DISTINCT FROM v_status_anterior;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATUALIZACAO_NAO_CONFIRMADA';
  END IF;

  -- Trigger SQL 17 gera exatamente um evento de transicao por status.
  RETURN jsonb_build_object(
    'ok',true,'protocolo',v_protocolo,
    'status_anterior',v_status_anterior,
    'status',v_status_normalizado,
    'executor_perfil',v_perfil,
    'completed_at',v_data_conclusao
  );
END
$status$;

REVOKE ALL ON FUNCTION public.v19_atualizar_status_chamado(uuid,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_atualizar_status_chamado(uuid,text)
  TO authenticated;

-- Continuamos usando apenas RPCs para alterar chamado ou historico.
REVOKE INSERT,UPDATE,DELETE
ON public.chamados,public.chamado_historico
FROM anon,authenticated;

COMMIT;

-- DIAGNOSTICO SEM ALTERACAO DE DADOS
SELECT 'RPC de status instalada' AS verificacao,
       CASE WHEN to_regprocedure(
         'public.v19_atualizar_status_chamado(uuid,text)') IS NOT NULL
       THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'Autenticados podem executar RPC',
       CASE WHEN has_function_privilege(
         'authenticated','public.v19_atualizar_status_chamado(uuid,text)','EXECUTE')
       THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Anonimo nao executa RPC',
       CASE WHEN NOT has_function_privilege(
         'anon','public.v19_atualizar_status_chamado(uuid,text)','EXECUTE')
       THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Historico automatico preservado',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
         WHERE tgrelid='public.chamados'::regclass
           AND tgname='trg_v19_historico_chamados'
           AND NOT tgisinternal) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'UPDATE direto continua bloqueado',
       CASE WHEN NOT has_table_privilege(
         'authenticated','public.chamados','UPDATE')
       THEN 'OK' ELSE 'FALHA' END;
