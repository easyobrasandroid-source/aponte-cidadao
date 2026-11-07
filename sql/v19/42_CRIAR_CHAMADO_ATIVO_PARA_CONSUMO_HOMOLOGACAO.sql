-- APONTE CIDADAO V19 / SQL 42
-- CHAMADO FICTICIO ATIVO PARA TESTE DE CONSUMO DE ESTOQUE
-- SOMENTE no projeto aponte-cidadao-v19-homologacao
-- NAO executa consumo, NAO altera o material ou o estoque e NAO toca V18.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $setup$
DECLARE
  v_consorcio uuid;
  v_cidade uuid;
  v_empresa uuid;
  v_material uuid;
  v_saldo numeric;
  v_contratado numeric;
BEGIN
  -- Verifica a base de teste, com dois consorcios.
  SELECT c.id INTO STRICT v_consorcio
  FROM public.consorcios c
  WHERE c.slug='teste-v19-alfa' AND c.status='ativo';

  IF NOT EXISTS (
    SELECT 1 FROM public.consorcios c
    WHERE c.slug='teste-v19-beta'
  ) OR to_regprocedure(
    'public.consumir_material_chamado(uuid,uuid,numeric)'
  ) IS NULL THEN
    RAISE EXCEPTION 'BASE_V19_OU_SQL41_NAO_CONFIRMADO';
  END IF;

  -- Cidade deve pertencer ao Consorcio Alfa.
  SELECT c.id INTO STRICT v_cidade
  FROM public.cidades c
  WHERE c.consorcio_id=v_consorcio
    AND c.nome='Municipio Alfa 1' AND c.status='ativo';

  -- Empresa Alfa B deve estar ativa e vinculada a esta cidade.
  SELECT e.id INTO STRICT v_empresa
  FROM public.empresas e
  JOIN public.empresa_cidades ec ON ec.empresa_id=e.id
  WHERE e.consorcio_id=v_consorcio
    AND e.nome='TESTE V19 - Empresa Alfa B'
    AND e.status='ativo'
    AND ec.cidade_id=v_cidade;

  -- Confere o material e saldo atuais, antes de criar fixture de teste.
  SELECT m.id,s.quantidade_disponivel,s.quantidade_contratada
    INTO STRICT v_material,v_saldo,v_contratado
  FROM public.materiais m
  JOIN public.estoques s
    ON s.material_id=m.id AND s.consorcio_id=m.consorcio_id
  WHERE m.consorcio_id=v_consorcio
    AND m.nome='V19-TESTE-ESTOQUE-ALFA-36'
    AND m.status='ativo';

  IF v_saldo<>14 OR v_contratado<>25 THEN
    RAISE EXCEPTION 'SALDO_INESPERADO: disponivel %, contratado %. Pare e confira o estoque.',
      v_saldo,v_contratado;
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.chamados
    WHERE protocolo='V19-TESTE-CONSUMO-ALFA-B-1'
  ) THEN
    RAISE EXCEPTION 'CHAMADO_JA_EXISTE_NAO_RECRIAR';
  END IF;

  INSERT INTO public.chamados (
    protocolo,consorcio_id,cidade_id,cidade,bairro,tipo,qtd,
    area,status,empresa_id,empresa,origem,observacoes
  )
  VALUES (
    'V19-TESTE-CONSUMO-ALFA-B-1',
    v_consorcio,v_cidade,'Municipio Alfa 1','Bairro Teste',
    'Luminaria LED apagada - teste de consumo',1,
    'Urbana','Em execução',v_empresa,'TESTE V19 - Empresa Alfa B',
    'Homologacao',
    'Chamado FICTICIO de homologacao de consumo. Nao usar em producao.'
  );
END
$setup$;

COMMIT;

-- O resultado esperado e UMA linha:
-- status Em execução; material disponivel 14; consumo 0.
SELECT
  c.protocolo,
  c.cidade,
  c.empresa,
  c.status,
  m.nome AS material_teste,
  s.quantidade_disponivel AS saldo_antes,
  s.quantidade_contratada AS contratado,
  (SELECT count(*)
   FROM public.chamado_materiais cm
   WHERE cm.chamado_id=c.id) AS consumos_no_chamado,
  (SELECT count(*)
   FROM public.movimentacoes mv
   WHERE mv.chamado_id=c.id) AS movimentacoes_do_chamado
FROM public.chamados c
JOIN public.materiais m ON m.consorcio_id=c.consorcio_id
 AND m.nome='V19-TESTE-ESTOQUE-ALFA-36'
JOIN public.estoques s ON s.material_id=m.id
 AND s.consorcio_id=c.consorcio_id
WHERE c.protocolo='V19-TESTE-CONSUMO-ALFA-B-1';
