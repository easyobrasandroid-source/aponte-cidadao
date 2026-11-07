-- APONTE CIDADÃO V19 — 04/05
-- Corrige isolamento entre empresas e bloqueia escritas diretas de estoque.
-- EXECUTAR SOMENTE DEPOIS de 03_rpc_estoque_transacional_NAO_APLICAR.sql
-- e dos testes na interface teste-v19/. NÃO aplicar na V18 sem homologação.
BEGIN;
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

COMMIT;

-- Não aplicar na produção até os testes dos perfis e da interface V19 passarem.
