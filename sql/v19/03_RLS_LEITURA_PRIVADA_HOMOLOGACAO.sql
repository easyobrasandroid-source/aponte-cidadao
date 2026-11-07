-- APONTE CIDADAO V19 / 03 - LEITURA PRIVADA POR PERFIL
-- SOMENTE para o projeto NOVO V19 de homologacao.
-- Precondicao: 01_BASE_LIMPA_HOMOLOGACAO.sql instalado e 02 aprovado.
-- Nao executa inserts, nao cria usuarios, nao habilita operacoes de escrita.
-- Rodar uma unica vez, e validar policies depois.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

-- Helpers SECURITY DEFINER sao criados pelo administrador do banco.
-- Consultam o Auth real; nenhuma permissao vem do navegador.
CREATE OR REPLACE FUNCTION public.v19_perfil_atual()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
 SELECT perfil FROM public.usuarios
 WHERE auth_user_id=(SELECT auth.uid()) AND status='ativo'
 LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.v19_consorcio_atual()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
 SELECT consorcio_id FROM public.usuarios
 WHERE auth_user_id=(SELECT auth.uid()) AND status='ativo'
 LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.v19_cidade_atual()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
 SELECT cidade_id FROM public.usuarios
 WHERE auth_user_id=(SELECT auth.uid()) AND status='ativo'
 LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.v19_empresa_atual()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
 SELECT empresa_id FROM public.usuarios
 WHERE auth_user_id=(SELECT auth.uid()) AND status='ativo'
 LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.v19_usuario_atual()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
 SELECT id FROM public.usuarios
 WHERE auth_user_id=(SELECT auth.uid()) AND status='ativo'
 LIMIT 1
$$;
-- Protecao de EXECUTE em RPCs de contexto.
REVOKE ALL ON FUNCTION public.v19_perfil_atual() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_consorcio_atual() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_cidade_atual() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_empresa_atual() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_usuario_atual() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_perfil_atual() TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_consorcio_atual() TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_cidade_atual() TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_empresa_atual() TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_usuario_atual() TO authenticated;

-- Privilegios SQL explicitos: a Data API pode ter exposicao automatica desligada.
-- As policies abaixo aplicam a filtragem de linhas somente apos GRANT SELECT.
REVOKE ALL ON public.consorcios,public.cidades,public.empresas,
 public.empresa_cidades,public.usuarios,public.equipes,public.chamados,
 public.chamado_historico,public.materiais,public.estoques,
 public.chamado_materiais,public.movimentacoes,public.sla_configuracoes,
 public.auditoria FROM anon;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON
 public.consorcios,public.cidades,public.empresas,public.empresa_cidades,
 public.usuarios,public.equipes,public.chamados,public.chamado_historico,
 public.materiais,public.estoques,public.chamado_materiais,
 public.movimentacoes,public.sla_configuracoes,public.auditoria
 FROM authenticated;
GRANT SELECT ON public.consorcios,public.cidades,public.empresas,
 public.empresa_cidades,public.usuarios,public.equipes,public.chamados,
 public.chamado_historico,public.materiais,public.estoques,
 public.chamado_materiais,public.movimentacoes,public.sla_configuracoes,
 public.auditoria TO authenticated;

-- Acesso somente SELECT: master ou tenant autorizado.
-- Fora destas policies, RLS continua bloqueando insercoes/updates/deletes.
CREATE POLICY v19_consorcios_sel ON public.consorcios FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR id=(SELECT public.v19_consorcio_atual()));
CREATE POLICY v19_cidades_sel ON public.cidades FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual())
    AND ((SELECT public.v19_perfil_atual()) IN ('consorcio','garantia')
      OR ((SELECT public.v19_perfil_atual())='prefeitura' AND id=(SELECT public.v19_cidade_atual()))
      OR ((SELECT public.v19_perfil_atual())='empresa'
        AND EXISTS(SELECT 1 FROM public.empresa_cidades ec
          WHERE ec.empresa_id=(SELECT public.v19_empresa_atual()) AND ec.cidade_id=cidades.id))
  )));
CREATE POLICY v19_empresas_sel ON public.empresas FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual())
    AND ((SELECT public.v19_perfil_atual())='consorcio'
      OR ((SELECT public.v19_perfil_atual())='empresa' AND id=(SELECT public.v19_empresa_atual())))));
CREATE POLICY v19_empresa_cidades_sel ON public.empresa_cidades FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
   OR ((SELECT public.v19_perfil_atual())='empresa' AND empresa_id=(SELECT public.v19_empresa_atual()))
   OR ((SELECT public.v19_perfil_atual())='consorcio' AND EXISTS(
     SELECT 1 FROM public.empresas e
     WHERE e.id=empresa_cidades.empresa_id AND e.consorcio_id=(SELECT public.v19_consorcio_atual())
   )));
CREATE POLICY v19_usuarios_sel ON public.usuarios FOR SELECT TO authenticated
 USING (id=(SELECT public.v19_usuario_atual())
  OR (SELECT public.v19_perfil_atual())='master'
  OR ((SELECT public.v19_perfil_atual())='consorcio'
    AND consorcio_id=(SELECT public.v19_consorcio_atual())));
CREATE POLICY v19_equipes_sel ON public.equipes FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual()) AND
   ((SELECT public.v19_perfil_atual())='consorcio'
    OR ((SELECT public.v19_perfil_atual())='empresa' AND empresa_id=(SELECT public.v19_empresa_atual())))));
CREATE POLICY v19_chamados_sel ON public.chamados FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual()) AND (
   (SELECT public.v19_perfil_atual())='consorcio'
   OR ((SELECT public.v19_perfil_atual())='prefeitura' AND cidade_id=(SELECT public.v19_cidade_atual()))
   OR ((SELECT public.v19_perfil_atual())='empresa' AND empresa_id=(SELECT public.v19_empresa_atual()))
   OR ((SELECT public.v19_perfil_atual())='garantia' AND
       (status='Aguardando Garantia LED' OR
        (status='Concluído' AND garantia_tipo IS NOT NULL)))
  )));
CREATE POLICY v19_historico_sel ON public.chamado_historico FOR SELECT TO authenticated
 USING (EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_id));
CREATE POLICY v19_materiais_sel ON public.materiais FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual())
    AND (SELECT public.v19_perfil_atual()) IN ('consorcio','empresa')));
CREATE POLICY v19_estoques_sel ON public.estoques FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual())
    AND (SELECT public.v19_perfil_atual()) IN ('consorcio','empresa')));
CREATE POLICY v19_movimentacoes_sel ON public.movimentacoes FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR (consorcio_id=(SELECT public.v19_consorcio_atual())
    AND (SELECT public.v19_perfil_atual())='consorcio'
  ));
CREATE POLICY v19_chamado_materiais_sel ON public.chamado_materiais FOR SELECT TO authenticated
 USING (EXISTS(SELECT 1 FROM public.chamados c WHERE c.id=chamado_id));
CREATE POLICY v19_sla_sel ON public.sla_configuracoes FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
  OR consorcio_id=(SELECT public.v19_consorcio_atual()));
CREATE POLICY v19_auditoria_sel ON public.auditoria FOR SELECT TO authenticated
 USING ((SELECT public.v19_perfil_atual())='master'
 OR (consorcio_id=(SELECT public.v19_consorcio_atual())
   AND (SELECT public.v19_perfil_atual())='consorcio'));

COMMIT;

-- A aplicacao continuara sem login funcional ate a configuracao Auth e
-- usuarios vinculados, e sem gravacoes ate a proxima migration autorizada.
SELECT tablename, count(*) AS numero_policies
FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'v19_%'
GROUP BY tablename ORDER BY tablename;
