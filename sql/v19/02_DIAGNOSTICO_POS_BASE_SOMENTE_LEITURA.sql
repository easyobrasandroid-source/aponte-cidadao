-- APONTE CIDADAO V19 / 02 - DIAGNOSTICO POS BASE (SOMENTE LEITURA)
-- Executar somente no projeto aponte-cidadao-v19-homologacao.
-- Objetivo: verificar estrutura e estado das policies antes de liberar API.
-- Esta consulta nao concede permissao e nao modifica tabelas.

WITH objetos(nome) AS (
 VALUES ('consorcios'),('cidades'),('empresas'),('empresa_cidades'),
        ('usuarios'),('equipes'),('chamados'),('chamado_historico'),
        ('materiais'),('estoques'),('chamado_materiais'),('movimentacoes'),
        ('sla_configuracoes'),('auditoria')
)
SELECT o.nome AS tabela, t.relname IS NOT NULL AS existe,
       coalesce(t.relrowsecurity,false) AS rls_ativo,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname='public' AND p.tablename=o.nome) AS numero_policies,
       CASE
         WHEN t.relname IS NULL THEN 'FALTA_TABELA'
         WHEN NOT t.relrowsecurity THEN 'FALTA_RLS'
         ELSE 'OK_ESTRUTURA'
       END AS diagnostico
FROM objetos o
LEFT JOIN pg_class t ON t.relname=o.nome
 AND t.relnamespace='public'::regnamespace AND t.relkind IN ('r','p')
ORDER BY o.nome;

-- O resultado esperado nesta fase sao 14 OK_ESTRUTURA.
-- numero_policies=0 indica que o acesso via RLS ainda nao foi habilitado,
-- mas nao substitui auditoria de GRANTs ou SECURITY DEFINER.
