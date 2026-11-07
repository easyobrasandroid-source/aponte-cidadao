-- APONTE CIDADÃO V19 / SQL60
-- Somente leitura: diagnosticar como são inseridos novos chamados para
-- preparar SLA automático em 2 dias urbanos e 5 dias rurais sem quebrar
-- as proteções de criação de prefeitura/empresa/portal.
-- Rodar APENAS no projeto Supabase V19 de homologação.
-- Não concede permissão, não instala gatilhos, não altera dados.
WITH
  t AS (
    SELECT tg.tgname AS objeto,
           CASE WHEN (tg.tgtype::integer & 2)=2 THEN 'BEFORE'
                ELSE 'AFTER' END AS tempo,
           pg_get_triggerdef(tg.oid, true) AS definicao
    FROM pg_trigger tg
    WHERE tg.tgrelid=to_regclass('public.chamados')
      AND NOT tg.tgisinternal
  ),
  r AS (
    SELECT p.proname AS objeto,
           pg_get_function_identity_arguments(p.oid) AS argumentos,
           p.prosecdef AS definer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'guard_chamados',
        'abrir_chamado_publico',
        'v19_salvar_sla_padrao'
      )
  ),
  slas AS (
    SELECT c.slug, s.urb_prazo, s.rur_prazo, s.urb_alerta, s.rur_alerta
    FROM public.consorcios c
    LEFT JOIN public.sla_configuracoes s
      ON s.consorcio_id=c.id AND s.tipo_problema='PADRAO_GERAL'
    WHERE c.slug IN ('teste-v19-alfa','teste-v19-beta')
  ),
  res (ordem,grupo,objeto,resultado,detalhe) AS (
    SELECT 1,'Ambiente','Consórcios de homologação',
      CASE WHEN (SELECT count(*) FROM public.consorcios
                   WHERE slug IN ('teste-v19-alfa','teste-v19-beta'))=2
           THEN 'OK' ELSE 'ALERTA' END,
      'Alfa e Beta devem estar presentes'
    UNION ALL
    SELECT 2,'Gatilho',t.objeto,'INFORMATIVO',
      t.tempo||' | '||t.definicao FROM t
    UNION ALL
    SELECT 3,'Rotina',r.objeto,'INFORMATIVO',
      'SECURITY DEFINER='||CASE WHEN r.definer THEN 'SIM' ELSE 'NAO' END||
      ' | parametros: '||r.argumentos FROM r
    UNION ALL
    SELECT 4,'Regra geral',s.slug,
      CASE WHEN s.slug='teste-v19-alfa'
                AND s.urb_prazo=48 AND s.rur_prazo=120 THEN 'OK'
           WHEN s.slug='teste-v19-beta' AND s.urb_prazo IS NULL
                AND s.rur_prazo IS NULL THEN 'OK_SEM_REGRA'
           ELSE 'ALERTA' END,
      'Urbano='||COALESCE(s.urb_prazo::text,'sem regra')||
      ' horas; rural='||COALESCE(s.rur_prazo::text,'sem regra')||
      ' horas; alertas='||COALESCE(s.urb_alerta::text,'-')||
      '/'||COALESCE(s.rur_alerta::text,'-')
    FROM slas s
    UNION ALL
    SELECT 5,'Chamados atuais',c.slug,'INFORMATIVO',
      'Total='||count(ch.id)::text||
      '; com SLA='||count(ch.id) FILTER (WHERE ch.sla_horas>0)::text||
      '; sem SLA='||count(ch.id) FILTER (WHERE ch.sla_horas IS NULL)::text
    FROM public.consorcios c
    LEFT JOIN public.chamados ch ON ch.consorcio_id=c.id
    WHERE c.slug IN ('teste-v19-alfa','teste-v19-beta')
    GROUP BY c.slug
  )
SELECT grupo,objeto,resultado,detalhe
FROM res ORDER BY ordem,objeto;
