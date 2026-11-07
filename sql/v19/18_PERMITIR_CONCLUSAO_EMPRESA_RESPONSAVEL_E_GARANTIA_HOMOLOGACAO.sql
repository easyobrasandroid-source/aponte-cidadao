-- APONTE CIDADAO V19 / SQL 18 - HOMOLOGACAO ISOLADA
-- Ajusta a regra de negocio: o chamado em Garantia LED pode ser concluido
-- (a) pelo tecnico Garantia do mesmo consorcio; ou
-- (b) pela empresa que JA ESTA ATRIBUIDA ao chamado E atende sua cidade.
-- Estar habilitada para a cidade, sem atribuicao, nao e suficiente.
-- NUNCA executar no Supabase V18/ambiente de producao.
-- Pre-requisito: SQL 17 ja instalado; chamado ficticio ainda em garantia.
-- Esta migracao NAO conclui chamados, NAO altera policy SELECT,
-- NAO concede UPDATE direto e NAO recria triggers.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $v19_protecao$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.consorcios
    WHERE slug='teste-v19-alfa'
  ) OR to_regprocedure('public.v19_concluir_garantia(uuid)') IS NULL
  OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.chamados'::regclass
      AND tgname='trg_v19_historico_chamados' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'PROJETO_DE_HOMOLOGACAO_OU_PRE_REQUISITOS_NAO_CONFIRMADOS';
  END IF;
END
$v19_protecao$;

CREATE OR REPLACE FUNCTION public.v19_concluir_garantia(p_chamado_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $conclusao$
DECLARE
  v_perfil text;
  v_consorcio uuid;
  v_empresa uuid;
  v_nome text;
  v_status text;
  v_garantia text;
  v_criacao timestamptz;
  v_concluido_em timestamptz;
  v_protocolo text;
  v_empresa_chamado uuid;
  v_cidade_chamado uuid;
  v_empresa_habilitada boolean;
  v_agora timestamptz;
BEGIN
  -- JWT real + usuario ativo e vinculado no banco.
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;
  IF p_chamado_id IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_OBRIGATORIO' USING ERRCODE='22023';
  END IF;

  SELECT u.perfil,u.consorcio_id,u.empresa_id,u.nome
    INTO v_perfil,v_consorcio,v_empresa,v_nome
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';

  IF NOT FOUND OR v_consorcio IS NULL
    OR v_perfil NOT IN ('garantia','empresa') THEN
    RAISE EXCEPTION 'PERFIL_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;

  -- Bloqueia o registro durante a checagem e a conclusao.
  SELECT c.status,c.garantia_tipo,c.created_at,c.completed_at,
         c.protocolo,c.empresa_id,c.cidade_id
    INTO v_status,v_garantia,v_criacao,v_concluido_em,
         v_protocolo,v_empresa_chamado,v_cidade_chamado
  FROM public.chamados c
  WHERE c.id=p_chamado_id AND c.consorcio_id=v_consorcio
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHAMADO_INEXISTENTE_OU_OUTRO_CONSORCIO'
      USING ERRCODE='42501';
  END IF;

  IF v_status IS DISTINCT FROM 'Aguardando Garantia LED'
     OR upper(btrim(coalesce(v_garantia,''))) <> 'LED'
     OR v_concluido_em IS NOT NULL THEN
    RAISE EXCEPTION 'CHAMADO_NAO_ELEGIVEL_OU_JA_CONCLUIDO'
      USING ERRCODE='22023';
  END IF;

  IF v_perfil='garantia' THEN
    -- O proprio consorcio ja foi verificado acima.
    IF v_empresa IS NOT NULL THEN
      RAISE EXCEPTION 'PERFIL_GARANTIA_COM_VINCULO_INDEVIDO'
        USING ERRCODE='42501';
    END IF;
  ELSE
    -- Empresa: atribucao E cidade contratualmente autorizada.
    IF v_empresa IS NULL
       OR v_empresa_chamado IS DISTINCT FROM v_empresa THEN
      RAISE EXCEPTION 'EMPRESA_NAO_ATRIBUIDA_AO_CHAMADO'
        USING ERRCODE='42501';
    END IF;
    SELECT EXISTS(
      SELECT 1
      FROM public.empresas e
      JOIN public.empresa_cidades ec ON ec.empresa_id=e.id
      JOIN public.cidades ci ON ci.id=ec.cidade_id
      WHERE e.id=v_empresa
        AND e.consorcio_id=v_consorcio AND e.status='ativo'
        AND ci.id=v_cidade_chamado
        AND ci.consorcio_id=v_consorcio AND ci.status='ativo'
    ) INTO v_empresa_habilitada;
    IF NOT coalesce(v_empresa_habilitada,false) THEN
      RAISE EXCEPTION 'EMPRESA_SEM_AUTORIZACAO_NA_CIDADE'
        USING ERRCODE='42501';
    END IF;
  END IF;

  v_agora:=clock_timestamp();
  IF v_agora < v_criacao THEN
    RAISE EXCEPTION 'DATA_DE_CONCLUSAO_INVALIDA' USING ERRCODE='22023';
  END IF;

  UPDATE public.chamados
     SET status='Concluído',
         completed_at=v_agora,
         garantia_dt=v_agora,
         garantia_user=v_nome,
         updated_at=v_agora
   WHERE id=p_chamado_id
     AND consorcio_id=v_consorcio
     AND status='Aguardando Garantia LED'
     AND completed_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CONCLUSAO_NAO_CONFIRMADA';
  END IF;

  -- Trigger do SQL 17 grava o historico da transicao automaticamente.
  RETURN jsonb_build_object('ok',true,'protocolo',v_protocolo,
                            'status','Concluído','completed_at',v_agora,
                            'executor_perfil',v_perfil);
END;
$conclusao$;

REVOKE ALL ON FUNCTION public.v19_concluir_garantia(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_concluir_garantia(uuid) TO authenticated;
-- Nao abrir escrita direta; somente a RPC SECURITY DEFINER faz a transicao.
REVOKE INSERT,UPDATE,DELETE ON public.chamados,public.chamado_historico
FROM anon,authenticated;

COMMIT;

SELECT 'RPC instalada' AS verificacao,
  CASE WHEN to_regprocedure('public.v19_concluir_garantia(uuid)') IS NOT NULL
    THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'Historico automatico preservado',
  CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.chamados'::regclass
      AND tgname='trg_v19_historico_chamados' AND NOT tgisinternal)
  THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPC bloqueada para anon',
  CASE WHEN NOT has_function_privilege(
    'anon','public.v19_concluir_garantia(uuid)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'UPDATE direto bloqueado',
  CASE WHEN NOT has_table_privilege(
    'authenticated','public.chamados','UPDATE')
  THEN 'OK' ELSE 'FALHA' END;
