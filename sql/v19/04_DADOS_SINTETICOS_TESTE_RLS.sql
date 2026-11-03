-- APONTE CIDADAO V19 / 04 - DADOS SINTETICOS PARA TESTE RLS
-- SOMENTE NO PROJETO aponte-cidadao-v19-homologacao.
-- Nao cria usuarios, nao insere dados pessoais, nao altera RLS.
-- Idempotente para os nomes/slug usados neste roteiro.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

INSERT INTO public.consorcios
 (nome,slug,portal_ativo,consulta_protocolo_ativo,abertura_portal_ativo,status)
VALUES
 ('TESTE V19 - Consorcio Alfa','teste-v19-alfa',false,false,false,'ativo'),
 ('TESTE V19 - Consorcio Beta','teste-v19-beta',false,false,false,'ativo')
ON CONFLICT(slug) DO NOTHING;

INSERT INTO public.cidades(consorcio_id,nome,uf,status)
SELECT c.id, v.nome,'MG','ativo'
FROM public.consorcios c
JOIN (VALUES
 ('teste-v19-alfa','Municipio Alfa 1'),
 ('teste-v19-alfa','Municipio Alfa 2'),
 ('teste-v19-beta','Municipio Beta 1')
) AS v(slug,nome) ON v.slug=c.slug
ON CONFLICT(consorcio_id,nome,uf) DO NOTHING;

INSERT INTO public.empresas(consorcio_id,nome,status)
SELECT c.id,v.nome,'ativo'
FROM public.consorcios c
JOIN (VALUES
 ('teste-v19-alfa','TESTE V19 - Empresa Alfa A'),
 ('teste-v19-alfa','TESTE V19 - Empresa Alfa B'),
 ('teste-v19-beta','TESTE V19 - Empresa Beta A')
) AS v(slug,nome) ON v.slug=c.slug
WHERE NOT EXISTS(
 SELECT 1 FROM public.empresas e
 WHERE e.consorcio_id=c.id AND e.nome=v.nome
);

-- Ambas empresas do Alfa atendem a cidade Alfa 1:
-- isso permite futuramente testar concorrencia em assumir um chamado.
INSERT INTO public.empresa_cidades(empresa_id,cidade_id)
SELECT e.id,ci.id
FROM public.empresas e
JOIN public.consorcios c ON c.id=e.consorcio_id
JOIN public.cidades ci ON ci.consorcio_id=c.id
WHERE
 (c.slug='teste-v19-alfa' AND
  e.nome IN ('TESTE V19 - Empresa Alfa A','TESTE V19 - Empresa Alfa B')
  AND ci.nome='Municipio Alfa 1')
 OR
 (c.slug='teste-v19-beta' AND
  e.nome='TESTE V19 - Empresa Beta A'
  AND ci.nome='Municipio Beta 1')
ON CONFLICT DO NOTHING;
COMMIT;

-- Retorno: 2 consorcios, 3 cidades, 3 empresas e 3 vinculos.
SELECT 'consorcios_teste' AS tipo,count(*) AS quantidade
 FROM public.consorcios WHERE slug IN ('teste-v19-alfa','teste-v19-beta')
UNION ALL
SELECT 'cidades_teste',count(*) FROM public.cidades ci
 JOIN public.consorcios c ON c.id=ci.consorcio_id
 WHERE c.slug IN ('teste-v19-alfa','teste-v19-beta')
UNION ALL
SELECT 'empresas_teste',count(*) FROM public.empresas e
 JOIN public.consorcios c ON c.id=e.consorcio_id
 WHERE c.slug IN ('teste-v19-alfa','teste-v19-beta')
UNION ALL
SELECT 'vinculos_empresa_cidade',count(*)
 FROM public.empresa_cidades ec
 JOIN public.empresas e ON e.id=ec.empresa_id
 JOIN public.consorcios c ON c.id=e.consorcio_id
 WHERE c.slug IN ('teste-v19-alfa','teste-v19-beta');
