-- Aponte Cidadão V19 — etapa de diagnóstico (SOMENTE LEITURA)
-- Bancos existentes: NÃO executar CREATE, DROP, GRANT, REVOKE ou UPDATE nesta etapa.
-- Verifica inconsistências que impediriam tornar o estoque estritamente transacional.
-- As contagens representam o momento da consulta, não são backup.

WITH diagnostico AS (
  SELECT 'estoques'::text AS modulo, 'total de linhas'::text AS verificacao,
         count(*)::bigint AS quantidade FROM public.estoques
  UNION ALL
  SELECT 'estoques','saldos disponíveis negativos',count(*) FROM public.estoques
   WHERE quantidade_disponivel < 0
  UNION ALL
  SELECT 'estoques','quantidades contratadas negativas',count(*) FROM public.estoques
   WHERE quantidade_contratada < 0
  UNION ALL
  SELECT 'estoques','saldos maiores que contratado (revisar regra de entradas)',count(*)
    FROM public.estoques WHERE quantidade_disponivel > quantidade_contratada
  UNION ALL
  SELECT 'estoques','material_id nulo',count(*) FROM public.estoques WHERE material_id IS NULL
  UNION ALL
  SELECT 'estoques','consorcio_id nulo',count(*) FROM public.estoques WHERE consorcio_id IS NULL
  UNION ALL
  SELECT 'estoques','pares material/consórcio duplicados',count(*)
    FROM (
      SELECT material_id,consorcio_id
      FROM public.estoques
      WHERE material_id IS NOT NULL AND consorcio_id IS NOT NULL
      GROUP BY material_id,consorcio_id
      HAVING count(*) > 1
    ) d
  UNION ALL
  SELECT 'estoques','consórcio do saldo diverge do material',count(*)
    FROM public.estoques e JOIN public.materiais m ON m.id=e.material_id
    WHERE e.consorcio_id IS DISTINCT FROM m.consorcio_id
  UNION ALL
  SELECT 'movimentacoes','total de movimentos',count(*) FROM public.movimentacoes
  UNION ALL
  SELECT 'movimentacoes','movimentos com quantidade nula ou não positiva',count(*)
    FROM public.movimentacoes WHERE quantidade IS NULL OR quantidade <= 0
  UNION ALL
  SELECT 'movimentacoes','consórcio do movimento diverge do material',count(*)
    FROM public.movimentacoes mv JOIN public.materiais m ON m.id=mv.material_id
    WHERE mv.consorcio_id IS DISTINCT FROM m.consorcio_id
  UNION ALL
  SELECT 'chamado_materiais','total de itens vinculados',count(*) FROM public.chamado_materiais
  UNION ALL
  SELECT 'chamado_materiais','itens com chamado_id ou material_id nulo',count(*)
    FROM public.chamado_materiais WHERE chamado_id IS NULL OR material_id IS NULL
  UNION ALL
  SELECT 'chamado_materiais','itens com quantidade nula ou não positiva',count(*)
    FROM public.chamado_materiais WHERE quantidade IS NULL OR quantidade <= 0
  UNION ALL
  SELECT 'chamado_materiais','material de outro consórcio do chamado',count(*)
    FROM public.chamado_materiais cm
    JOIN public.chamados ch ON ch.id=cm.chamado_id
    JOIN public.materiais m ON m.id=cm.material_id
    WHERE ch.consorcio_id IS DISTINCT FROM m.consorcio_id
)
SELECT modulo, verificacao, quantidade
FROM diagnostico
ORDER BY modulo, verificacao;
