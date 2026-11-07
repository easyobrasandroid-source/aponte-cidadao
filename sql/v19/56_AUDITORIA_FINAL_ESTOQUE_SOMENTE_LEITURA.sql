-- APONTE CIDADAO V19 / SQL 56
-- AUDITORIA FINAL DOS TESTES DE ESTOQUE 36–55
-- SOMENTE LEITURA. NENHUMA ALTERACAO NO BANCO.
-- EXECUTAR SOMENTE NO aponte-cidadao-v19-homologacao.

WITH
material_teste AS (
  SELECT m.id,m.consorcio_id,m.nome
  FROM public.materiais m
  JOIN public.consorcios c ON c.id=m.consorcio_id
  WHERE m.nome='V19-TESTE-ESTOQUE-ALFA-36'
    AND c.slug='teste-v19-alfa'
),
estoque_teste AS (
  SELECT s.* FROM public.estoques s
  JOIN material_teste m ON m.id=s.material_id
   AND m.consorcio_id=s.consorcio_id
),
movimentos_teste AS (
  SELECT mv.* FROM public.movimentacoes mv
  JOIN material_teste m ON m.id=mv.material_id
),
movimentos_calculo AS (
  SELECT
    COUNT(*) AS registros,
    COUNT(*) FILTER (
       WHERE tipo NOT IN ('entrada','saida','consumo','devolucao','estorno')
    ) AS tipos_desconhecidos,
    COALESCE(SUM(
      CASE
        WHEN tipo IN ('entrada','devolucao','estorno') THEN quantidade
        WHEN tipo IN ('saida','consumo') THEN -quantidade
        ELSE 0
      END
    ),0) AS saldo_reconstituido
  FROM movimentos_teste
),
chamado_teste AS (
  SELECT ch.* FROM public.chamados ch
  WHERE ch.protocolo='V19-TESTE-CONSUMO-ALFA-B-1'
),
consumo_teste AS (
  SELECT COUNT(*) AS itens_ativos
  FROM public.chamado_materiais cm
  JOIN chamado_teste ch ON ch.id=cm.chamado_id
),
historico_teste AS (
  SELECT COUNT(*) AS eventos
  FROM public.chamado_historico h
  JOIN chamado_teste ch ON ch.id=h.chamado_id
),
integridade_tenant AS (
  SELECT
    (
     SELECT count(*)
     FROM public.movimentacoes mv
     JOIN public.materiais m ON m.id=mv.material_id
     WHERE mv.consorcio_id IS DISTINCT FROM m.consorcio_id
    ) AS movimentos_de_outro_consorcio,
    (
     SELECT count(*)
     FROM public.chamado_materiais cm
     JOIN public.chamados ch ON ch.id=cm.chamado_id
     JOIN public.materiais m ON m.id=cm.material_id
     WHERE ch.consorcio_id IS DISTINCT FROM m.consorcio_id
    ) AS itens_de_outro_consorcio,
    (
     SELECT count(*)
     FROM public.movimentacoes mv
     JOIN public.chamados ch ON ch.id=mv.chamado_id
     WHERE mv.chamado_id IS NOT NULL
       AND mv.consorcio_id IS DISTINCT FROM ch.consorcio_id
    ) AS movimentos_chamado_de_outro_consorcio,
    (
     SELECT count(*)
     FROM public.estoques s
     WHERE s.quantidade_disponivel<0
        OR s.quantidade_disponivel>s.quantidade_contratada
    ) AS saldos_invalidos
),
checagens AS (
  SELECT 1 AS ordem,'Material de teste unico' AS verificacao,
    CASE WHEN (SELECT count(*) FROM material_teste)=1
      THEN 'OK' ELSE 'REVISAR' END AS resultado,
    (SELECT count(*)::text FROM material_teste) AS detalhe
  UNION ALL
  SELECT 2,'Estoque do material unico',
    CASE WHEN (SELECT count(*) FROM estoque_teste)=1
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT count(*)::text FROM estoque_teste)
  UNION ALL
  SELECT 3,'Saldo disponivel final',
    CASE WHEN (SELECT count(*) FROM estoque_teste)=1
      AND (SELECT quantidade_disponivel FROM estoque_teste)=14
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT coalesce(max(quantidade_disponivel)::text,'AUSENTE')
       FROM estoque_teste)
  UNION ALL
  SELECT 4,'Quantidade contratada final',
    CASE WHEN (SELECT count(*) FROM estoque_teste)=1
      AND (SELECT quantidade_contratada FROM estoque_teste)=25
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT coalesce(max(quantidade_contratada)::text,'AUSENTE')
       FROM estoque_teste)
  UNION ALL
  SELECT 5,'Movimentacoes registradas',
    CASE WHEN (SELECT registros FROM movimentos_calculo)=7
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT registros::text FROM movimentos_calculo)
  UNION ALL
  SELECT 6,'Saldo igual a soma das movimentacoes',
    CASE WHEN (SELECT tipos_desconhecidos FROM movimentos_calculo)=0
      AND (SELECT count(*) FROM estoque_teste)=1
      AND (SELECT saldo_reconstituido FROM movimentos_calculo)=
          (SELECT quantidade_disponivel FROM estoque_teste)
      THEN 'OK' ELSE 'REVISAR' END,
    'movimentos='||(SELECT saldo_reconstituido::text FROM movimentos_calculo)
    ||'; estoque='||(SELECT coalesce(max(quantidade_disponivel)::text,'AUSENTE')
                      FROM estoque_teste)
  UNION ALL
  SELECT 7,'Chamado ficticio unico e em execucao',
    CASE WHEN (SELECT count(*) FROM chamado_teste)=1
      AND (SELECT status FROM chamado_teste)='Em execução'
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT coalesce(max(status),'AUSENTE') FROM chamado_teste)
  UNION ALL
  SELECT 8,'Sem itens de consumo ativos',
    CASE WHEN (SELECT itens_ativos FROM consumo_teste)=0
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT itens_ativos::text FROM consumo_teste)
  UNION ALL
  SELECT 9,'Historico com quatro eventos',
    CASE WHEN (SELECT eventos FROM historico_teste)=4
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT eventos::text FROM historico_teste)
  UNION ALL
  SELECT 10,'Sem divergencias de consorcio',
    CASE WHEN (SELECT movimentos_de_outro_consorcio+
                 itens_de_outro_consorcio+
                 movimentos_chamado_de_outro_consorcio
               FROM integridade_tenant)=0
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT (movimentos_de_outro_consorcio+
             itens_de_outro_consorcio+
             movimentos_chamado_de_outro_consorcio)::text
       FROM integridade_tenant)
  UNION ALL
  SELECT 11,'Sem saldos negativos ou acima do contratado',
    CASE WHEN (SELECT saldos_invalidos FROM integridade_tenant)=0
      THEN 'OK' ELSE 'REVISAR' END,
    (SELECT saldos_invalidos::text FROM integridade_tenant)
)
SELECT verificacao,resultado,detalhe
FROM checagens
ORDER BY ordem;
