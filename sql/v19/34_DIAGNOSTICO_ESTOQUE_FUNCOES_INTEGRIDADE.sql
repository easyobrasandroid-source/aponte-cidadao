-- APONTE CIDADAO V19 / SQL 34
-- ESTOQUE: FUNCOES DISPONIVEIS E INTEGRIDADE MULTICONSORCIO
-- 100% SOMENTE LEITURA. NAO INSTALA NADA.
-- Rodar EXCLUSIVAMENTE no projeto V19 de homologacao.
WITH
funcoes(descricao, assinatura, ordem) AS (
  VALUES
    ('RPC cadastro de material',
     'public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)',1),
    ('RPC movimentacao manual',
     'public.v19_movimentar_estoque(uuid,text,numeric,text)',2),
    ('RPC consumo por chamado',
     'public.consumir_material_chamado(uuid,uuid,numeric)',3),
    ('RPC consumo V19 alternativo',
     'public.v19_consumir_material_chamado(uuid,uuid,numeric)',4)
),
rpc AS (
  SELECT descricao,assinatura,ordem,to_regprocedure(assinatura) AS oid
  FROM funcoes
),
verificacoes AS (
  SELECT ordem,
    descricao AS verificacao,
    CASE WHEN oid IS NULL THEN 'NAO INSTALADA'
         ELSE 'INSTALADA' END AS resultado,
    CASE WHEN oid IS NULL THEN assinatura
         ELSE 'retorno=' || pg_get_function_result(oid)
           || '; autenticado=' ||
             CASE WHEN has_function_privilege('authenticated',oid::oid,'EXECUTE')
                  THEN 'SIM' ELSE 'NAO' END
           || '; anonimo=' ||
             CASE WHEN has_function_privilege('anon',oid::oid,'EXECUTE')
                  THEN 'SIM' ELSE 'NAO' END
    END AS detalhe
  FROM rpc

  UNION ALL
  SELECT 5,'Materiais cadastrados','INFORMATIVO',
         count(*)::text FROM public.materiais
  UNION ALL
  SELECT 6,'Linhas de estoque','INFORMATIVO',
         count(*)::text FROM public.estoques
  UNION ALL
  SELECT 7,'Movimentacoes existentes','INFORMATIVO',
         count(*)::text FROM public.movimentacoes
  UNION ALL
  SELECT 8,'Consumos associados a chamados','INFORMATIVO',
         count(*)::text FROM public.chamado_materiais

  UNION ALL
  SELECT 9,'Saldo disponivel acima do contratado',
         CASE WHEN count(*)=0 THEN 'ZERO OCORRENCIAS' ELSE 'REVISAR' END,
         count(*)::text
  FROM public.estoques
  WHERE quantidade_disponivel>quantidade_contratada

  UNION ALL
  SELECT 10,'Estoque duplicado por material/consorcio',
         CASE WHEN count(*)=0 THEN 'ZERO OCORRENCIAS' ELSE 'REVISAR' END,
         count(*)::text
  FROM (
    SELECT material_id,consorcio_id
    FROM public.estoques
    GROUP BY material_id,consorcio_id
    HAVING count(*)>1
  ) duplicados

  UNION ALL
  SELECT 11,'Movimento com consorcio divergente',
         CASE WHEN count(*)=0 THEN 'ZERO OCORRENCIAS' ELSE 'REVISAR' END,
         count(*)::text
  FROM public.movimentacoes v
  JOIN public.materiais m ON m.id=v.material_id
  WHERE v.consorcio_id IS DISTINCT FROM m.consorcio_id

  UNION ALL
  SELECT 12,'Consumo de material de outro consorcio',
         CASE WHEN count(*)=0 THEN 'ZERO OCORRENCIAS' ELSE 'REVISAR' END,
         count(*)::text
  FROM public.chamado_materiais cm
  JOIN public.chamados ch ON ch.id=cm.chamado_id
  JOIN public.materiais m ON m.id=cm.material_id
  WHERE ch.consorcio_id IS DISTINCT FROM m.consorcio_id
)
SELECT verificacao,resultado,detalhe
FROM verificacoes
ORDER BY ordem;
