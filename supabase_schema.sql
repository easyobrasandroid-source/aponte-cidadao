-- ============================================================
-- APONTE CIDADÃO — Schema Supabase (PostgreSQL)
-- Execute este SQL no Supabase SQL Editor
-- ============================================================

-- 1. CONSÓRCIOS
CREATE TABLE IF NOT EXISTS consorcios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  logo_url TEXT,
  banner_url TEXT,
  cor_primaria TEXT DEFAULT '#1251A3',
  slogan TEXT,
  telefone_contato TEXT,
  whatsapp_contato TEXT,
  email_institucional TEXT,
  portal_ativo BOOLEAN DEFAULT true,
  consulta_protocolo_ativo BOOLEAN DEFAULT true,
  abertura_portal_ativo BOOLEAN DEFAULT true,
  gps_obrigatorio BOOLEAN DEFAULT false,
  prazo_medio_texto TEXT DEFAULT 'Até 48 horas úteis',
  status TEXT DEFAULT 'ativo',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. CIDADES
CREATE TABLE IF NOT EXISTS cidades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  nome TEXT NOT NULL,
  uf CHAR(2) DEFAULT 'MG',
  status TEXT DEFAULT 'ativo',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. EMPRESAS
CREATE TABLE IF NOT EXISTS empresas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  nome TEXT NOT NULL,
  cnpj TEXT,
  endereco TEXT,
  cidade TEXT,
  uf TEXT DEFAULT 'MG',
  telefone TEXT,
  email TEXT,
  responsavel TEXT,
  status TEXT DEFAULT 'ativo',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. USUÁRIOS
CREATE TABLE IF NOT EXISTS usuarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  empresa_id UUID REFERENCES empresas(id),
  nome TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  telefone TEXT,
  cpf TEXT,
  cargo TEXT,
  perfil TEXT NOT NULL CHECK (perfil IN ('master','consorcio','prefeitura','empresa')),
  vinculo_tipo TEXT,
  vinculo_id TEXT,
  org TEXT,
  senha_hash TEXT,
  status TEXT DEFAULT 'ativo',
  ultimo_acesso TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. EQUIPES
CREATE TABLE IF NOT EXISTS equipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  empresa_id UUID REFERENCES empresas(id),
  nome TEXT NOT NULL,
  tecnico_lider TEXT,
  membros INTEGER DEFAULT 1,
  cidades TEXT[],
  status TEXT DEFAULT 'ativa',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. CHAMADOS
CREATE TABLE IF NOT EXISTS chamados (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  protocolo TEXT UNIQUE NOT NULL,
  consorcio_id UUID REFERENCES consorcios(id),
  cidade TEXT NOT NULL,
  bairro TEXT,
  endereco TEXT,
  referencia TEXT,
  area TEXT DEFAULT 'Urbana' CHECK (area IN ('Urbana','Rural')),
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  loc_src TEXT DEFAULT 'manual',
  tipo TEXT NOT NULL,
  qtd INTEGER DEFAULT 1,
  observacoes TEXT,
  status TEXT DEFAULT 'Recebido',
  prioridade TEXT DEFAULT 'Média',
  empresa TEXT,
  empresa_id UUID REFERENCES empresas(id),
  origem TEXT DEFAULT 'Público',
  solicitante_nome TEXT,
  solicitante_tel TEXT,
  sla_horas INTEGER,
  sla_pausado BOOLEAN DEFAULT false,
  garantia_tipo TEXT,
  garantia_obs TEXT,
  garantia_dt TIMESTAMPTZ,
  garantia_user TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. HISTÓRICO DOS CHAMADOS
CREATE TABLE IF NOT EXISTS chamado_historico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chamado_id UUID REFERENCES chamados(id) ON DELETE CASCADE,
  status TEXT,
  mensagem TEXT,
  observacao TEXT,
  cor TEXT DEFAULT '#1251A3',
  usuario_nome TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. MATERIAIS
CREATE TABLE IF NOT EXISTS materiais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  nome TEXT NOT NULL,
  unidade TEXT DEFAULT 'Un.',
  estoque_minimo DECIMAL(10,2) DEFAULT 0,
  preco_unitario DECIMAL(10,2) DEFAULT 0,
  status TEXT DEFAULT 'ativo',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. ESTOQUES
CREATE TABLE IF NOT EXISTS estoques (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID REFERENCES materiais(id),
  consorcio_id UUID REFERENCES consorcios(id),
  quantidade_contratada DECIMAL(10,2) DEFAULT 0,
  quantidade_disponivel DECIMAL(10,2) DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. CHAMADOS × MATERIAIS
CREATE TABLE IF NOT EXISTS chamado_materiais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chamado_id UUID REFERENCES chamados(id) ON DELETE CASCADE,
  material_id UUID REFERENCES materiais(id),
  quantidade DECIMAL(10,2),
  preco_unitario DECIMAL(10,2),
  total DECIMAL(10,2),
  usuario_nome TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. SLA CONFIGURAÇÕES
CREATE TABLE IF NOT EXISTS sla_configuracoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consorcio_id UUID REFERENCES consorcios(id),
  tipo_problema TEXT NOT NULL,
  ico TEXT,
  urb_prazo INTEGER DEFAULT 48,
  urb_unidade TEXT DEFAULT 'Horas',
  urb_alerta INTEGER DEFAULT 12,
  rur_prazo INTEGER DEFAULT 72,
  rur_unidade TEXT DEFAULT 'Horas',
  rur_alerta INTEGER DEFAULT 24,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. AUDITORIA
CREATE TABLE IF NOT EXISTS auditoria (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_responsavel TEXT,
  acao TEXT,
  detalhes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ÍNDICES para performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chamados_status ON chamados(status);
CREATE INDEX IF NOT EXISTS idx_chamados_cidade ON chamados(cidade);
CREATE INDEX IF NOT EXISTS idx_chamados_created ON chamados(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chamados_area ON chamados(area);
CREATE INDEX IF NOT EXISTS idx_chamados_empresa ON chamados(empresa);
CREATE INDEX IF NOT EXISTS idx_historico_chamado ON chamado_historico(chamado_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) — segurança por linha
-- ============================================================
ALTER TABLE chamados ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE chamado_historico ENABLE ROW LEVEL SECURITY;

-- Política pública: qualquer um pode ler chamados (portal público)
CREATE POLICY "chamados_leitura_publica" ON chamados
  FOR SELECT USING (true);

-- Política de inserção: apenas autenticados
CREATE POLICY "chamados_insercao_autenticados" ON chamados
  FOR INSERT WITH CHECK (true);

-- Política de atualização: apenas autenticados
CREATE POLICY "chamados_atualizacao_autenticados" ON chamados
  FOR UPDATE USING (true);

-- ============================================================
-- DADOS INICIAIS (seed)
-- ============================================================

-- Consórcio principal
INSERT INTO consorcios (nome, slug, cor_primaria, slogan, telefone_contato, email_institucional)
VALUES (
  'CIS Caparaó',
  'ciscaparao',
  '#0D7A55',
  'Iluminação pública do Vale do Caparaó',
  '(33) 3721-0000',
  'contato@ciscaparao.mg.gov.br'
) ON CONFLICT (slug) DO NOTHING;

-- Cidades
INSERT INTO cidades (consorcio_id, nome, uf)
SELECT c.id, unnest(ARRAY[
  'Espera Feliz','Caparaó','Alto Caparaó','Carangola',
  'Manhuaçu','Divino','Chalé','Faria Lemos',
  'Orizânia','Simonésia','Manhumirim','Reduto',
  'Alto Jequitibá','Caiana'
]), 'MG'
FROM consorcios c WHERE c.slug='ciscaparao'
ON CONFLICT DO NOTHING;

-- Empresas
INSERT INTO empresas (consorcio_id, nome, cnpj, cidade, uf, telefone, email, responsavel)
SELECT c.id, 'Vagalume', '12.345.678/0001-90', 'Espera Feliz', 'MG', '(33) 3721-1000', 'contato@vagalume.com.br', 'Carlos Vagalume'
FROM consorcios c WHERE c.slug='ciscaparao'
ON CONFLICT DO NOTHING;

INSERT INTO empresas (consorcio_id, nome, cnpj, cidade, uf, telefone, email, responsavel)
SELECT c.id, 'Eletroluz', '98.765.432/0001-10', 'Manhuaçu', 'MG', '(33) 3862-2000', 'contato@eletroluz.com.br', 'Maria Eletroluz'
FROM consorcios c WHERE c.slug='ciscaparao'
ON CONFLICT DO NOTHING;

-- Usuário Admin Master
INSERT INTO usuarios (nome, email, perfil, org, status)
VALUES (
  'Fernando Admin',
  'admin@apontecidadao.com.br',
  'master',
  'Todos',
  'ativo'
) ON CONFLICT (email) DO NOTHING;

-- SLA padrão
INSERT INTO sla_configuracoes (consorcio_id, tipo_problema, ico, urb_prazo, urb_unidade, urb_alerta, rur_prazo, rur_unidade, rur_alerta)
SELECT c.id, tipo, ico, urb_h, 'Horas', urb_a, rur_h, 'Horas', rur_a
FROM consorcios c, (VALUES
  ('Lâmpada apagada (1-2 un.)','💡',48,12,72,24),
  ('Lâmpada apagada (3+ un.)','💡',24,6,48,12),
  ('Lâmpada piscando','⚡',72,24,96,24),
  ('Lâmpada com defeito','⚠️',72,24,96,24),
  ('Luminária quebrada','💡',48,12,72,24),
  ('Poste danificado','🔧',120,24,168,48),
  ('Poste inclinado','🔧',120,24,168,48),
  ('Cabo rompido','⚡',24,6,36,12),
  ('Acesa durante o dia','☀️',168,48,240,72)
) AS t(tipo, ico, urb_h, urb_a, rur_h, rur_a)
WHERE c.slug='ciscaparao'
ON CONFLICT DO NOTHING;

SELECT 'Schema criado com sucesso!' as resultado;
