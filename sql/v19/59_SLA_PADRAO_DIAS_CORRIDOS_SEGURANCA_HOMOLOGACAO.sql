-- APONTE CIDADÃO V19 / SQL 59 — SLA PADRÃO EM DIAS CORRIDOS
-- SOMENTE HOMOLOGAÇÃO, NUNCA PRODUÇÃO/V18.
-- DECISÃO DO RESPONSÁVEL: URBANO 2 DIAS / RURAL 5 DIAS, PROVISÓRIOS.
-- UNIDADE DE EXIBIÇÃO = DIA CORRIDO. ARMAZENAMENTO = HORAS EXATAS.
--
-- Este arquivo:
-- (a) instala RPC segura para posterior alteração por master/gestor do consórcio;
-- (b) cria UMA regra PADRAO_GERAL no Consórcio Alfa de homologação (48/120 horas);
-- (c) NÃO altera nenhum chamado já aberto ou concluído, nenhum histórico,
--     nenhum prazo específico existente, nenhuma regra de outro consórcio.
-- Importante: a regra só deverá ser aplicada a NOVOS chamados em futura
-- integração segura de abertura/atribuição de SLA; este SQL não retroage.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $gate$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.consorcios WHERE slug='teste-v19-alfa' AND status='ativo'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.consorcios WHERE slug='teste-v19-beta'
  ) OR (
    SELECT count(*)
    FROM public.chamados
    WHERE protocolo IN ('V19-TESTE-UI-GARANTIA-ALFA-A-57',
                        'V19-TESTE-UI-GARANTIA-ALFA-B-57')
      AND status='Concluído'
  ) <> 2 OR
  to_regprocedure('public.v19_concluir_garantia(uuid)') IS NULL
  THEN
    RAISE EXCEPTION 'AMBIENTE_NAO_EH_V19_HOMOLOGACAO_CONFIRMADA';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.sla_configuracoes s
    JOIN public.consorcios c ON c.id=s.consorcio_id
    WHERE c.slug='teste-v19-alfa' AND s.tipo_problema='PADRAO_GERAL'
  ) THEN
    RAISE EXCEPTION 'SLA_PADRAO_JA_CADASTRADO_NAO_REEXECUTAR';
  END IF;
END
$gate$;

CREATE OR REPLACE FUNCTION public.v19_salvar_sla_padrao(
  p_consorcio_id uuid,
  p_urb_dias integer,
  p_rur_dias integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $rpc$
DECLARE
  v_perfil text;
  v_consorcio_usuario uuid;
  v_nome text;
  v_rule_id uuid;
  v_atual_urb integer;
  v_atual_rur integer;
  v_agora timestamptz;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  SELECT u.perfil,u.consorcio_id,u.nome
    INTO v_perfil,v_consorcio_usuario,v_nome
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo'
  LIMIT 1;

  IF NOT FOUND OR v_perfil NOT IN ('master','consorcio') THEN
    RAISE EXCEPTION 'PERFIL_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;
  IF p_consorcio_id IS NULL OR
     (v_perfil='consorcio' AND v_consorcio_usuario IS DISTINCT FROM p_consorcio_id)
  THEN
    RAISE EXCEPTION 'CONSORCIO_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;
  IF p_urb_dias IS NULL OR p_rur_dias IS NULL OR
     p_urb_dias NOT BETWEEN 1 AND 365 OR p_rur_dias NOT BETWEEN 1 AND 365
  THEN
    RAISE EXCEPTION 'PRAZO_EM_DIAS_INVALIDO' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.consorcios c
                 WHERE c.id=p_consorcio_id AND c.status='ativo')
  THEN
    RAISE EXCEPTION 'CONSORCIO_INATIVO_OU_INEXISTENTE' USING ERRCODE='42501';
  END IF;

  SELECT s.id,s.urb_prazo,s.rur_prazo
    INTO v_rule_id,v_atual_urb,v_atual_rur
  FROM public.sla_configuracoes s
  WHERE s.consorcio_id=p_consorcio_id
    AND s.tipo_problema='PADRAO_GERAL'
  FOR UPDATE;

  -- Não cria regras escondidas por RPC: a configuração deve ter sido
  -- provisionada/homologada para o consórcio com procedimento próprio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REGRA_PADRAO_NAO_CONFIGURADA' USING ERRCODE='22023';
  END IF;

  v_agora=clock_timestamp();
  UPDATE public.sla_configuracoes
  SET urb_prazo=p_urb_dias*24,
      rur_prazo=p_rur_dias*24,
      urb_unidade='Horas',
      rur_unidade='Horas',
      updated_at=v_agora
  WHERE id=v_rule_id AND consorcio_id=p_consorcio_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATUALIZACAO_SLA_NAO_CONFIRMADA';
  END IF;

  -- Histórico administrativo desta alteração, sem alterar chamados.
  INSERT INTO public.auditoria
    (consorcio_id,usuario_responsavel,acao,detalhes)
  VALUES
    (p_consorcio_id,COALESCE(v_nome,'Usuário autenticado'),
     'SLA_PADRAO_ALTERADO',
     'Regra PADRAO_GERAL; urbano '||COALESCE(v_atual_urb::text,'nulo')||
     'h -> '||(p_urb_dias*24)::text||'h; rural '||
     COALESCE(v_atual_rur::text,'nulo')||'h -> '||
     (p_rur_dias*24)::text||'h; contagem em dias corridos');

  RETURN jsonb_build_object(
    'ok',true,'consorcio_id',p_consorcio_id,'tipo_problema','PADRAO_GERAL',
    'urb_dias',p_urb_dias,'rur_dias',p_rur_dias
  );
END;
$rpc$;

REVOKE ALL ON FUNCTION public.v19_salvar_sla_padrao(uuid,integer,integer)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_salvar_sla_padrao(uuid,integer,integer)
  TO authenticated;
-- Nenhum usuário do navegador recebe escrita direta nas tabelas.
REVOKE INSERT,UPDATE,DELETE ON public.sla_configuracoes,public.auditoria
  FROM anon,authenticated;

INSERT INTO public.sla_configuracoes
  (consorcio_id,tipo_problema,urb_prazo,urb_unidade,urb_alerta,
   rur_prazo,rur_unidade,rur_alerta)
SELECT c.id,'PADRAO_GERAL',48,'Horas',NULL,120,'Horas',NULL
FROM public.consorcios c
WHERE c.slug='teste-v19-alfa' AND c.status='ativo';
COMMIT;

-- Diagnóstico final: 8 verificações; configuração única para Alfa.
SELECT 'Projeto Alfa V19 encontrado' verificacao,
  CASE WHEN EXISTS(SELECT 1 FROM public.consorcios WHERE slug='teste-v19-alfa')
  THEN 'OK' ELSE 'FALHA' END resultado
UNION ALL SELECT 'Regra PADRAO_GERAL única para Alfa',
  CASE WHEN (SELECT count(*) FROM public.sla_configuracoes s
    JOIN public.consorcios c ON c.id=s.consorcio_id
    WHERE c.slug='teste-v19-alfa' AND s.tipo_problema='PADRAO_GERAL')=1
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Prazo urbano 2 dias corridos (48 horas)',
  CASE WHEN EXISTS(SELECT 1 FROM public.sla_configuracoes s
    JOIN public.consorcios c ON c.id=s.consorcio_id
    WHERE c.slug='teste-v19-alfa' AND s.tipo_problema='PADRAO_GERAL'
      AND s.urb_prazo=48 AND s.urb_unidade='Horas')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Prazo rural 5 dias corridos (120 horas)',
  CASE WHEN EXISTS(SELECT 1 FROM public.sla_configuracoes s
    JOIN public.consorcios c ON c.id=s.consorcio_id
    WHERE c.slug='teste-v19-alfa' AND s.tipo_problema='PADRAO_GERAL'
      AND s.rur_prazo=120 AND s.rur_unidade='Horas')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Alertas não definidos, sem inventar prazos',
  CASE WHEN EXISTS(SELECT 1 FROM public.sla_configuracoes s
    JOIN public.consorcios c ON c.id=s.consorcio_id
    WHERE c.slug='teste-v19-alfa' AND s.tipo_problema='PADRAO_GERAL'
      AND s.urb_alerta IS NULL AND s.rur_alerta IS NULL)
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'RPC de edição disponível a authenticated',
  CASE WHEN has_function_privilege('authenticated',
    'public.v19_salvar_sla_padrao(uuid,integer,integer)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'RPC de edição negada a anon',
  CASE WHEN NOT has_function_privilege('anon',
    'public.v19_salvar_sla_padrao(uuid,integer,integer)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Gravação direta de SLA negada a authenticated',
  CASE WHEN NOT has_table_privilege('authenticated','public.sla_configuracoes','UPDATE')
  THEN 'OK' ELSE 'FALHA' END;
