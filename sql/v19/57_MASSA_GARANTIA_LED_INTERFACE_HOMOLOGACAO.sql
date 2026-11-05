-- APONTE CIDADAO V19 / SQL 57
-- DUAS FIXTURES DE GARANTIA LED PARA HOMOLOGACAO DA INTERFACE
-- EXECUTE SOMENTE NO SQL EDITOR DO PROJETO V19 HOMOLOGACAO.
-- NUNCA EXECUTE NA V18 / PRODUCAO.
--
-- CRIA exatamente 2 CHAMADOS FICTICIOS PENDENTES:
--   V19-TESTE-UI-GARANTIA-ALFA-A-57 (empresa Alfa A)
--   V19-TESTE-UI-GARANTIA-ALFA-B-57 (empresa Alfa B)
-- NAO atualiza chamados antigos, NAO cria contas, NAO altera RLS/RPCs,
-- NAO conclui nenhum chamado e NAO altera historico existente.
-- Operacao transacional e intencionalmente NAO reexecutavel.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $fixture$
DECLARE
  v_consorcio uuid;
  v_cidade uuid;
  v_nome_cidade text;
  v_empresa_a uuid;
  v_nome_a text;
  v_empresa_b uuid;
  v_nome_b text;
BEGIN
  SELECT id INTO v_consorcio
    FROM public.consorcios WHERE slug='teste-v19-alfa' AND status='ativo';

  IF v_consorcio IS NULL
     OR to_regprocedure('public.v19_concluir_garantia(uuid)') IS NULL
     OR to_regprocedure('public.v19_atualizar_status_chamado(uuid,text)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.chamados
       WHERE protocolo='V19-TESTE-RLS-ALFA-A'
         AND consorcio_id=v_consorcio
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.usuarios
       WHERE email='garantiaalfa@aponte.test'
         AND perfil='garantia' AND status='ativo'
         AND consorcio_id=v_consorcio AND auth_user_id IS NOT NULL
     )
  THEN
    RAISE EXCEPTION 'PROJETO_V19_OU_PRE_REQUISITOS_NAO_CONFIRMADOS';
  END IF;

  SELECT id,nome INTO v_cidade,v_nome_cidade
    FROM public.cidades
   WHERE consorcio_id=v_consorcio AND nome='Municipio Alfa 1'
     AND status='ativo';
  IF v_cidade IS NULL THEN
    RAISE EXCEPTION 'MUNICIPIO_ALFA_1_NAO_ENCONTRADO';
  END IF;

  SELECT id,nome INTO v_empresa_a,v_nome_a
    FROM public.empresas
   WHERE consorcio_id=v_consorcio
     AND nome='TESTE V19 - Empresa Alfa A' AND status='ativo';
  SELECT id,nome INTO v_empresa_b,v_nome_b
    FROM public.empresas
   WHERE consorcio_id=v_consorcio
     AND nome='TESTE V19 - Empresa Alfa B' AND status='ativo';

  IF v_empresa_a IS NULL OR v_empresa_b IS NULL OR v_empresa_a=v_empresa_b
     OR NOT EXISTS (
       SELECT 1 FROM public.empresa_cidades
       WHERE empresa_id=v_empresa_a AND cidade_id=v_cidade
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.empresa_cidades
       WHERE empresa_id=v_empresa_b AND cidade_id=v_cidade
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.usuarios
       WHERE perfil='empresa' AND status='ativo'
         AND empresa_id=v_empresa_a AND consorcio_id=v_consorcio
         AND auth_user_id IS NOT NULL
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.usuarios
       WHERE perfil='empresa' AND status='ativo'
         AND empresa_id=v_empresa_b AND consorcio_id=v_consorcio
         AND auth_user_id IS NOT NULL
     )
  THEN
    RAISE EXCEPTION 'EMPRESAS_OU_VINCULOS_DE_CIDADE_NAO_CONFIRMADOS';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.chamados
    WHERE protocolo IN (
      'V19-TESTE-UI-GARANTIA-ALFA-A-57',
      'V19-TESTE-UI-GARANTIA-ALFA-B-57'
    )
  ) THEN
    RAISE EXCEPTION 'FIXTURE_57_JA_EXISTE_NAO_REEXECUTAR';
  END IF;

  INSERT INTO public.chamados
  (protocolo,consorcio_id,cidade_id,cidade,area,tipo,qtd,observacoes,
   status,empresa,empresa_id,origem,garantia_tipo,completed_at,garantia_dt,garantia_user)
  VALUES
  ('V19-TESTE-UI-GARANTIA-ALFA-A-57',v_consorcio,v_cidade,v_nome_cidade,
   'Urbana','Luminaria LED com defeito - teste de interface',1,
   'HOMOLOGACAO V19 / SQL 57 / fixture Alfa A / nao e chamado real',
   'Aguardando Garantia LED',v_nome_a,v_empresa_a,'Homologacao','LED',NULL,NULL,NULL),
  ('V19-TESTE-UI-GARANTIA-ALFA-B-57',v_consorcio,v_cidade,v_nome_cidade,
   'Urbana','Luminaria LED com defeito - teste de interface',1,
   'HOMOLOGACAO V19 / SQL 57 / fixture Alfa B / nao e chamado real',
   'Aguardando Garantia LED',v_nome_b,v_empresa_b,'Homologacao','LED',NULL,NULL,NULL);
END
$fixture$;

COMMIT;

-- SOMENTE LEITURA. Resultado esperado: exatamente 2 linhas pendentes, 0 historicos.
SELECT c.protocolo,c.cidade,c.empresa,c.status,c.garantia_tipo,
       (c.completed_at IS NULL) AS conclusao_pendente,
       (SELECT count(*) FROM public.chamado_historico h
        WHERE h.chamado_id=c.id) AS registros_historico
FROM public.chamados c
WHERE c.protocolo IN (
  'V19-TESTE-UI-GARANTIA-ALFA-A-57',
  'V19-TESTE-UI-GARANTIA-ALFA-B-57'
)
ORDER BY c.protocolo;
