-- Aponte Cidadão V19 — auditoria de permissões em HOMOLOGAÇÃO
-- SOMENTE LEITURA. Não cria, altera ou exclui dados.
-- Executar no SQL Editor do Supabase de HOMOLOGAÇÃO depois das migrations.
-- ATENÇÃO: sucesso deste diagnóstico não substitui testes reais com JWT
-- de perfis Consórcio, Prefeitura, Empresa A, Empresa B e Garantia.
BEGIN READ ONLY;

-- 1. Tabelas com RLS ligado e forçado (RLS forçado é informativo;
-- os owners e funções SECURITY DEFINER exigem auditoria própria).
SELECT n.nspname AS esquema, c.relname AS tabela,
       c.relrowsecurity AS rls_ativo, c.relforcerowsecurity AS rls_forcado,
       CASE WHEN c.relrowsecurity THEN 'OK_RLS_ATIVO'
            ELSE 'ALERTA_RLS_DESLIGADO' END AS resultado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p')
  AND c.relname IN (
    'chamados','chamado_historico','usuarios','empresas',
    'empresa_cidades','cidades','materiais','estoques',
    'movimentacoes','equipes','sla_configuracoes'
  )
ORDER BY c.relname;

-- 2. Políticas efetivamente instaladas (inspecionar USING e WITH CHECK,
-- não basta que a tabela tenha RLS ligado).
SELECT schemaname, tablename, policyname, permissive, roles, cmd,
       qual AS using_expr, with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN (
    'chamados','chamado_historico','usuarios','empresas',
    'empresa_cidades','cidades','materiais','estoques',
    'movimentacoes','equipes','sla_configuracoes'
  )
ORDER BY tablename, policyname;

-- 3. RPCs V19 expostas para authenticated e, indevidamente, para anon/PUBLIC.
-- has_function_privilege('anon',...) avalia permissões herdadas de PUBLIC.
SELECT p.proname AS rpc,
       pg_get_function_identity_arguments(p.oid) AS assinatura,
       p.prosecdef AS security_definer,
       has_function_privilege('authenticated',p.oid,'EXECUTE')
         AS authenticated_executa,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_executa,
       CASE WHEN has_function_privilege('anon',p.oid,'EXECUTE')
            THEN 'ALERTA_EXECUCAO_PUBLICA'
            ELSE 'OK_EXECUCAO_RESTRITA' END AS resultado
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname LIKE 'v19_%'
ORDER BY p.proname, assinatura;

-- 4. Funções críticas de atribuição: devem existir e não ser executáveis
-- por anon. A ausência também deve ser tratada como falha de implantação.
WITH funcs(nome, assinatura) AS (
 VALUES ('v19_listar_disponiveis','integer'),
        ('v19_assumir_chamado','uuid')
)
SELECT f.nome, f.assinatura,
       to_regprocedure('public.'||f.nome||'('||f.assinatura||')') IS NOT NULL
         AS existe,
       CASE
         WHEN to_regprocedure('public.'||f.nome||'('||f.assinatura||')') IS NULL
           THEN 'FALHA_RPC_AUSENTE'
         WHEN has_function_privilege(
           'anon',to_regprocedure('public.'||f.nome||'('||f.assinatura||')'),
           'EXECUTE') THEN 'FALHA_ANON_EXECUTA'
         ELSE 'OK'
       END AS resultado
FROM funcs f;

-- 5. Objetos e triggers relacionados ao registro de histórico/garantia.
SELECT event_object_table AS tabela, trigger_name, action_timing,
       event_manipulation, action_statement
FROM information_schema.triggers
WHERE event_object_schema='public'
  AND event_object_table IN ('chamados','chamado_historico')
ORDER BY event_object_table, trigger_name, event_manipulation;

-- 6. SQL não mede isolamento tenant. Testar com duas empresas e JWTs
-- distintos: SELECT direto /rest/v1/chamados, UPDATE indevido, RPC de fila,
-- corrida de atribuição e acesso a fotos de outros consórcios.
ROLLBACK;
