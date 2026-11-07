-- APONTE CIDADAO V19 / SQL 22
-- NOVO CHAMADO FICTICIO PARA TESTE DE CONCLUSAO PELO PERFIL GARANTIA
-- EXECUTAR SOMENTE EM aponte-cidadao-v19-homologacao
-- Requer os SQLs 17 e 18 instalados. Nao modifica o chamado do Teste 21.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios
                 WHERE slug='teste-v19-alfa') THEN
    RAISE EXCEPTION 'Consorcio Alfa de homologacao nao encontrado';
  END IF;
  IF EXISTS (SELECT 1 FROM public.chamados
             WHERE protocolo='V19-TESTE-GARANTIA-ALFA-2') THEN
    RAISE EXCEPTION 'Chamado de teste 22 ja existe: nao recriar nem reiniciar status';
  END IF;
END
$pre$;

-- Atribuimos este novo chamado a Empresa Alfa B: o tecnico Garantia
-- podera conclui-lo por pertencer ao seu consorcio, independentemente
-- de qual empresa daquele consorcio e a responsavel.
INSERT INTO public.chamados (
  protocolo,consorcio_id,cidade_id,cidade,tipo,qtd,status,
  empresa_id,empresa,origem,area,garantia_tipo,garantia_obs,observacoes
)
SELECT
  'V19-TESTE-GARANTIA-ALFA-2',
  c.id,ci.id,ci.nome,
  'Luminaria LED com defeito',1,'Aguardando Garantia LED',
  e.id,e.nome,'Homologacao','Urbana','LED',
  'Teste positivo de conclusao pelo perfil Garantia Alfa',
  'REGISTRO FICTICIO - NAO USAR EM PRODUCAO'
FROM public.consorcios c
JOIN public.cidades ci ON ci.consorcio_id=c.id
JOIN public.empresas e ON e.consorcio_id=c.id
JOIN public.empresa_cidades ec
  ON ec.empresa_id=e.id AND ec.cidade_id=ci.id
WHERE c.slug='teste-v19-alfa'
  AND ci.nome='Municipio Alfa 1'
  AND e.nome='TESTE V19 - Empresa Alfa B';

DO $check$
BEGIN
  IF (SELECT COUNT(*) FROM public.chamados
      WHERE protocolo='V19-TESTE-GARANTIA-ALFA-2'
        AND status='Aguardando Garantia LED'
        AND garantia_tipo='LED'
        AND completed_at IS NULL
  ) <> 1 THEN
    RAISE EXCEPTION 'Chamado de teste 22 nao foi criado como esperado';
  END IF;
END
$check$;
COMMIT;

-- Resultado esperado: uma linha, sem data de conclusao.
SELECT ch.protocolo,ch.cidade,ch.empresa,ch.status,
       ch.garantia_tipo,
       (ch.completed_at IS NULL) AS conclusao_pendente
FROM public.chamados ch
WHERE ch.protocolo='V19-TESTE-GARANTIA-ALFA-2';
