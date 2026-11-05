-- APONTE CIDADÃO V19 — AUDITORIA CONSOLIDADA / SQL 58
-- SOMENTE LEITURA: UMA consulta SELECT, sem INSERT/UPDATE/DELETE/DDL/RPC.
-- Executar EXCLUSIVAMENTE no Supabase V19 de HOMOLOGAÇÃO.
-- NÃO executar na V18 ou produção.
-- NÃO simula sessões JWT de empresas: permissões de SQL são apenas
-- diagnóstico complementar aos testes reais por usuário autenticado.
WITH
  esperados(protocolo) AS (
    VALUES
      ('V19-TESTE-UI-GARANTIA-ALFA-A-57'),
      ('V19-TESTE-UI-GARANTIA-ALFA-B-57')
  ),
  garantia AS (
    SELECT c.protocolo,c.status,c.completed_at,
           (SELECT COUNT(*) FROM public.chamado_historico h
             WHERE h.chamado_id=c.id) AS eventos
    FROM public.chamados c
    JOIN esperados e ON e.protocolo=c.protocolo
  ),
  project AS (
    SELECT id FROM public.consorcios
     WHERE slug='teste-v19-alfa'
  ),
  sla AS (
    SELECT
      (SELECT COUNT(*) FROM public.chamados c
        WHERE c.consorcio_id IN (SELECT id FROM project)) AS chamados,
      (SELECT COUNT(*) FROM public.chamados c
        WHERE c.consorcio_id IN (SELECT id FROM project)
          AND (c.sla_horas IS NULL OR c.sla_horas<=0)) AS sem_prazo,
      (SELECT COUNT(*) FROM public.chamados c
        WHERE c.consorcio_id IN (SELECT id FROM project)
          AND c.sla_horas>0) AS com_prazo,
      (SELECT COUNT(*) FROM public.sla_configuracoes cfg
        WHERE cfg.consorcio_id IN (SELECT id FROM project)) AS regras,
      (SELECT COUNT(*) FROM public.chamados c
        WHERE c.consorcio_id IN (SELECT id FROM project)
          AND c.sla_pausado IS TRUE) AS pausados
  ),
  checks(ordem,verificacao,resultado,detalhe) AS (
    SELECT 1,'Projeto de homologação Alfa',
      CASE WHEN (SELECT COUNT(*) FROM project)=1 THEN 'OK' ELSE 'ALERTA' END,
      'Consórcios correspondentes ao slug teste-v19-alfa: '||(SELECT COUNT(*) FROM project)::text
    UNION ALL SELECT 2,'RLS ativo: chamados',
      CASE WHEN EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relname='chamados' AND c.relrowsecurity)
       THEN 'OK' ELSE 'ALERTA' END,
      'RLS habilitado (não substitui auditoria de políticas e JWT)'
    UNION ALL SELECT 3,'RLS ativo: chamado_historico',
      CASE WHEN EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relname='chamado_historico' AND c.relrowsecurity)
       THEN 'OK' ELSE 'ALERTA' END,
      'Histórico protegido por RLS'
    UNION ALL SELECT 4,'Escrita direta bloqueada: authenticated',
      CASE WHEN NOT has_table_privilege('authenticated','public.chamados','UPDATE')
            AND NOT has_table_privilege('authenticated','public.chamado_historico','INSERT')
       THEN 'OK' ELSE 'ALERTA' END,
      'UPDATE de chamados e INSERT no histórico devem passar por RPC/trigger'
    UNION ALL SELECT 5,'Escrita direta bloqueada: anon',
      CASE WHEN NOT has_table_privilege('anon','public.chamados','UPDATE')
            AND NOT has_table_privilege('anon','public.chamado_historico','INSERT')
       THEN 'OK' ELSE 'ALERTA' END,
      'Sem privilégios de edição para visitantes anônimos'
    UNION ALL SELECT 6,'RPC Garantia LED instalada',
      CASE WHEN to_regprocedure('public.v19_concluir_garantia(uuid)') IS NOT NULL THEN 'OK' ELSE 'ALERTA' END,
      'public.v19_concluir_garantia(uuid)'
    UNION ALL SELECT 7,'RPC conclusão comum instalada',
      CASE WHEN to_regprocedure('public.v19_atualizar_status_chamado(uuid,text)') IS NOT NULL THEN 'OK' ELSE 'ALERTA' END,
      'public.v19_atualizar_status_chamado(uuid,text)'
    UNION ALL SELECT 8,'RPCs restritas a authenticated',
      CASE WHEN
        to_regprocedure('public.v19_concluir_garantia(uuid)') IS NOT NULL
        AND to_regprocedure('public.v19_atualizar_status_chamado(uuid,text)') IS NOT NULL
        AND has_function_privilege('authenticated',
          to_regprocedure('public.v19_concluir_garantia(uuid)'),'EXECUTE')
        AND has_function_privilege('authenticated',
          to_regprocedure('public.v19_atualizar_status_chamado(uuid,text)'),'EXECUTE')
        AND NOT has_function_privilege('anon',
          to_regprocedure('public.v19_concluir_garantia(uuid)'),'EXECUTE')
        AND NOT has_function_privilege('anon',
          to_regprocedure('public.v19_atualizar_status_chamado(uuid,text)'),'EXECUTE')
       THEN 'OK' ELSE 'ALERTA' END,
      'EXECUTE authenticated=sim e anon=não nas duas funções'
    UNION ALL SELECT 9,'Garantias 57 concluídas',
      CASE WHEN (SELECT COUNT(*) FROM garantia)=2
        AND (SELECT COUNT(*) FROM garantia
          WHERE status='Concluído' AND completed_at IS NOT NULL)=2
       THEN 'OK' ELSE 'ALERTA' END,
      'Localizadas='||(SELECT COUNT(*) FROM garantia)::text||
      '; concluídas='||(SELECT COUNT(*) FROM garantia
          WHERE status='Concluído' AND completed_at IS NOT NULL)::text
    UNION ALL SELECT 10,'Histórico único em cada garantia 57',
      CASE WHEN (SELECT COUNT(*) FROM garantia)=2
        AND (SELECT COUNT(*) FROM garantia WHERE eventos=1)=2
       THEN 'OK' ELSE 'ALERTA' END,
      'Registros por chamado: '||COALESCE(
        (SELECT string_agg(protocolo||'='||eventos::text,'; ' ORDER BY protocolo)
         FROM garantia),'nenhum')
    UNION ALL SELECT 11,'SLA: prazo registrado nos chamados Alfa',
      'INFORMATIVO',
      'Total='||sla.chamados::text||
      '; com prazo válido='||sla.com_prazo::text||
      '; sem prazo válido='||sla.sem_prazo::text||
      '; pausados='||sla.pausados::text FROM sla
    UNION ALL SELECT 12,'SLA: regras cadastradas no Consórcio Alfa',
      CASE WHEN sla.regras=0 THEN 'SEM_REGRAS' ELSE 'INFORMATIVO' END,
      'Total de regras em sla_configuracoes='||sla.regras::text||
      '; regras não são automaticamente aplicadas ao chamado sem vínculo validado'
      FROM sla
    UNION ALL SELECT 13,'SLA: método contratual',
      'PENDENTE',
      'Horas corridas são apenas estimativa; validar calendário, horário útil, pausa e regras de vencimento'
  )
SELECT verificacao,resultado,detalhe
  FROM checks
 ORDER BY ordem;
