-- APONTE CIDADAO V19 - SQL 26
-- CHAMADO FICTICIO DISPONIVEL PARA DISPUTA ALFA A X ALFA B
-- SOMENTE EM aponte-cidadao-v19-homologacao
-- Nao altera as RPCs, usuarios, policies nem chamados existentes.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $v19$
DECLARE
    v_consorcio_id UUID;
    v_cidade_id UUID;
    v_qtd_empresas INTEGER;
BEGIN
    SELECT id INTO STRICT v_consorcio_id
    FROM public.consorcios
    WHERE slug = 'teste-v19-alfa';

    SELECT id INTO STRICT v_cidade_id
    FROM public.cidades
    WHERE consorcio_id = v_consorcio_id
      AND nome = 'Municipio Alfa 1';

    SELECT COUNT(DISTINCT e.id)
    INTO v_qtd_empresas
    FROM public.empresas e
    JOIN public.empresa_cidades ec
      ON ec.empresa_id = e.id
    WHERE e.consorcio_id = v_consorcio_id
      AND e.status = 'ativo'
      AND ec.cidade_id = v_cidade_id
      AND e.nome IN (
        'TESTE V19 - Empresa Alfa A',
        'TESTE V19 - Empresa Alfa B'
      );

    IF v_qtd_empresas <> 2 THEN
        RAISE EXCEPTION
          'As duas empresas Alfa nao estao habilitadas nesta cidade';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.chamados
        WHERE protocolo = 'V19-TESTE-ATRIBUICAO-ALFA-1'
    ) THEN
        RAISE EXCEPTION
          'Chamado de teste ja existe. Nao recriar nem reiniciar a atribuicao';
    END IF;

    INSERT INTO public.chamados (
        protocolo,
        consorcio_id,
        cidade_id,
        cidade,
        bairro,
        tipo,
        qtd,
        status,
        empresa_id,
        empresa,
        origem,
        area,
        observacoes
    ) VALUES (
        'V19-TESTE-ATRIBUICAO-ALFA-1',
        v_consorcio_id,
        v_cidade_id,
        'Municipio Alfa 1',
        'Bairro Teste',
        'Luminaria apagada - teste de concorrencia',
        1,
        'Recebido',
        NULL,
        NULL,
        'Homologacao',
        'Urbana',
        'Registro ficticio: disputa entre empresas Alfa A e Alfa B'
    );
END $v19$;

COMMIT;

-- DIAGNOSTICO FINAL: UMA LINHA, empresa_id NULL,
-- status Recebido e historico 0
SELECT
    ch.protocolo,
    ch.cidade,
    ch.status,
    (ch.empresa_id IS NULL) AS sem_empresa_atribuida,
    (SELECT count(*)
     FROM public.chamado_historico h
     WHERE h.chamado_id = ch.id) AS registros_historico
FROM public.chamados ch
WHERE ch.protocolo = 'V19-TESTE-ATRIBUICAO-ALFA-1';
