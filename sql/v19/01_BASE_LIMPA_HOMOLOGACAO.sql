-- APONTE CIDADAO V19 / 01 - BASE LIMPA DE HOMOLOGACAO
-- USAR SOMENTE NO PROJETO NOVO aponte-cidadao-v19-homologacao.
-- Nao executar no projeto V18. Nao cria seeds, usuarios ou politicas publicas.
-- Este arquivo cria a base estrutural; NAO executar 08 ainda.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE public.consorcios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 nome text NOT NULL, slug text NOT NULL UNIQUE,
 logo_url text, banner_url text, cor_primaria text DEFAULT '#1251A3',
 slogan text, telefone_contato text, whatsapp_contato text,
 email_institucional text, portal_ativo boolean NOT NULL DEFAULT false,
 consulta_protocolo_ativo boolean NOT NULL DEFAULT false,
 abertura_portal_ativo boolean NOT NULL DEFAULT false,
 gps_obrigatorio boolean NOT NULL DEFAULT false,
 prazo_medio_texto text, status text NOT NULL DEFAULT 'ativo',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.cidades (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 nome text NOT NULL, uf char(2) NOT NULL DEFAULT 'MG',
 status text NOT NULL DEFAULT 'ativo',
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,consorcio_id), UNIQUE(consorcio_id,nome,uf)
);
CREATE TABLE public.empresas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 nome text NOT NULL, cnpj text, endereco text, cidade text,
 uf text DEFAULT 'MG', telefone text, email text, responsavel text,
 status text NOT NULL DEFAULT 'ativo',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,consorcio_id)
);
CREATE TABLE public.empresa_cidades (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
 cidade_id uuid NOT NULL REFERENCES public.cidades(id) ON DELETE CASCADE,
 PRIMARY KEY(empresa_id,cidade_id)
);
CREATE TABLE public.usuarios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
 consorcio_id uuid REFERENCES public.consorcios(id),
 cidade_id uuid REFERENCES public.cidades(id),
 empresa_id uuid REFERENCES public.empresas(id),
 nome text NOT NULL, email text NOT NULL UNIQUE, telefone text, cpf text,
 cargo text, perfil text NOT NULL CHECK(perfil IN
 ('master','consorcio','prefeitura','empresa','garantia')),
 vinculo_tipo text, vinculo_id text, org text,
 status text NOT NULL DEFAULT 'ativo',
 ultimo_acesso timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT usuarios_escopo CHECK(
  (perfil='master' AND consorcio_id IS NULL AND empresa_id IS NULL AND cidade_id IS NULL)
  OR (perfil='consorcio' AND consorcio_id IS NOT NULL AND empresa_id IS NULL)
  OR (perfil='prefeitura' AND consorcio_id IS NOT NULL AND cidade_id IS NOT NULL AND empresa_id IS NULL)
  OR (perfil='empresa' AND consorcio_id IS NOT NULL AND empresa_id IS NOT NULL)
  OR (perfil='garantia' AND consorcio_id IS NOT NULL AND empresa_id IS NULL)
 )
);
CREATE TABLE public.equipes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 empresa_id uuid REFERENCES public.empresas(id),
 nome text NOT NULL, tecnico_lider text, membros integer NOT NULL DEFAULT 1
 CHECK(membros>=0),
 cidades text[], status text NOT NULL DEFAULT 'ativa',
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.chamados (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 protocolo text NOT NULL UNIQUE,
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 cidade_id uuid NOT NULL,
 cidade text NOT NULL, bairro text, endereco text, referencia text,
 area text NOT NULL DEFAULT 'Urbana' CHECK(area IN ('Urbana','Rural')),
 latitude numeric(10,8) CHECK(latitude BETWEEN -90 AND 90),
 longitude numeric(11,8) CHECK(longitude BETWEEN -180 AND 180),
 loc_src text DEFAULT 'manual', tipo text NOT NULL,
 qtd integer NOT NULL DEFAULT 1 CHECK(qtd>0),
 observacoes text, status text NOT NULL DEFAULT 'Recebido',
 prioridade text DEFAULT 'Média', empresa text,
 empresa_id uuid REFERENCES public.empresas(id),
 origem text DEFAULT 'Público', solicitante_nome text, solicitante_tel text,
 sla_horas integer CHECK(sla_horas IS NULL OR sla_horas>=0),
 sla_pausado boolean NOT NULL DEFAULT false, garantia_tipo text,
 garantia_obs text, garantia_dt timestamptz, garantia_user text,
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(cidade_id,consorcio_id) REFERENCES public.cidades(id,consorcio_id)
);
CREATE TABLE public.chamado_historico (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 chamado_id uuid NOT NULL REFERENCES public.chamados(id) ON DELETE CASCADE,
 status text, mensagem text, observacao text, cor text DEFAULT '#1251A3',
 usuario_nome text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.materiais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 nome text NOT NULL, unidade text NOT NULL DEFAULT 'Un.',
 estoque_minimo numeric(14,2) NOT NULL DEFAULT 0 CHECK(estoque_minimo>=0),
 preco_unitario numeric(14,2) NOT NULL DEFAULT 0 CHECK(preco_unitario>=0),
 status text NOT NULL DEFAULT 'ativo',
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,consorcio_id)
);
CREATE TABLE public.estoques (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 material_id uuid NOT NULL, consorcio_id uuid NOT NULL,
 quantidade_contratada numeric(14,2) NOT NULL DEFAULT 0 CHECK(quantidade_contratada>=0),
 quantidade_disponivel numeric(14,2) NOT NULL DEFAULT 0 CHECK(quantidade_disponivel>=0),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(material_id,consorcio_id) REFERENCES public.materiais(id,consorcio_id),
 UNIQUE(material_id,consorcio_id)
);
CREATE TABLE public.chamado_materiais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 chamado_id uuid NOT NULL REFERENCES public.chamados(id) ON DELETE CASCADE,
 material_id uuid NOT NULL REFERENCES public.materiais(id),
 quantidade numeric(14,2) NOT NULL CHECK(quantidade>0),
 preco_unitario numeric(14,2) CHECK(preco_unitario>=0),
 total numeric(14,2) CHECK(total>=0), usuario_nome text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.movimentacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 material_id uuid NOT NULL REFERENCES public.materiais(id),
 chamado_id uuid REFERENCES public.chamados(id),
 tipo text NOT NULL,
 quantidade numeric(14,2) NOT NULL CHECK(quantidade>0),
 usuario_nome text, usuario_id uuid REFERENCES public.usuarios(id),
 origem text, observacao text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.sla_configuracoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid NOT NULL REFERENCES public.consorcios(id),
 tipo_problema text NOT NULL, ico text,
 urb_prazo integer DEFAULT 48, urb_unidade text DEFAULT 'Horas',
 urb_alerta integer DEFAULT 12, rur_prazo integer DEFAULT 72,
 rur_unidade text DEFAULT 'Horas', rur_alerta integer DEFAULT 24,
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(consorcio_id,tipo_problema)
);
CREATE TABLE public.auditoria (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consorcio_id uuid REFERENCES public.consorcios(id),
 usuario_responsavel text, acao text, detalhes text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_chamados_consorcio_created ON public.chamados(consorcio_id,created_at DESC);
CREATE INDEX idx_chamados_cidade_status ON public.chamados(cidade_id,status);
CREATE INDEX idx_chamados_empresa ON public.chamados(empresa_id);
CREATE INDEX idx_historico_chamado ON public.chamado_historico(chamado_id,created_at DESC);
CREATE INDEX idx_movimentos_material ON public.movimentacoes(material_id,created_at DESC);
CREATE INDEX idx_usuarios_escopo ON public.usuarios(consorcio_id,perfil);

-- Bloqueio por padrao: nenhuma policy de acesso ao navegador nesta fase.
DO $$
DECLARE item text;
BEGIN
 FOREACH item IN ARRAY ARRAY[
 'consorcios','cidades','empresas','empresa_cidades','usuarios','equipes',
 'chamados','chamado_historico','materiais','estoques','chamado_materiais',
 'movimentacoes','sla_configuracoes','auditoria'
 ] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',item);
 END LOOP;
END $$;
COMMIT;

-- Diagnostico apos executar em homologacao (consulta somente leitura):
SELECT c.relname AS tabela, c.relrowsecurity AS rls_ativo
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
ORDER BY c.relname;
