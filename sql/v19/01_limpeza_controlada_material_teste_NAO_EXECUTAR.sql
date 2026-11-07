-- APONTE CIDADÃO — V19
-- MIGRATION EM RASCUNHO / NÃO EXECUTAR NO BANCO SEM BACKUP E APROVAÇÃO
-- Finalidade: remover SOMENTE o cadastro de teste V18 sem consórcio e seu estoque.
-- NÃO é correção de permissões: separar limpeza de dados da migration de RLS.
-- Evidências: Supabase Snippet Untitled query (10)-(13).csv, 2026-11-03.
-- Alvos exatos:
-- materiais.id = fc35c185-2a84-476a-9262-97637efc4508
-- estoques.id = 350cd419-6124-4b0d-9526-f0aa674dd365
-- Nenhuma alteração será efetuada até o script ser executado manualmente.
-- Se qualquer pré-condição falhar, a transação é abortada.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
DECLARE
  v_material_id uuid := 'fc35c185-2a84-476a-9262-97637efc4508';
  v_estoque_id uuid := '350cd419-6124-4b0d-9526-f0aa674dd365';
  v_material_nome text;
  v_material_consorcio uuid;
  v_estoque_consorcio uuid;
  v_contratada numeric;
  v_disponivel numeric;
  v_rows integer;
BEGIN
  SELECT m.nome, m.consorcio_id
    INTO v_material_nome, v_material_consorcio
    FROM public.materiais m
   WHERE m.id = v_material_id
     FOR UPDATE;

  IF NOT FOUND
     OR v_material_nome IS DISTINCT FROM 'TESTE V18 MASTER 29102026 - NAO UTILIZAR'
     OR v_material_consorcio IS NOT NULL
  THEN
    RAISE EXCEPTION 'ABORTADO: material de teste não corresponde ao esperado.';
  END IF;

  SELECT e.consorcio_id, e.quantidade_contratada, e.quantidade_disponivel
    INTO v_estoque_consorcio, v_contratada, v_disponivel
    FROM public.estoques e
   WHERE e.id = v_estoque_id
     AND e.material_id = v_material_id
     FOR UPDATE;

  IF NOT FOUND
     OR v_estoque_consorcio IS NOT NULL
     OR v_contratada IS DISTINCT FROM 2
     OR v_disponivel IS DISTINCT FROM 1
     OR (SELECT count(*) FROM public.estoques WHERE material_id = v_material_id) <> 1
  THEN
    RAISE EXCEPTION 'ABORTADO: estoque mudou ou não corresponde à auditoria.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.chamado_materiais WHERE material_id = v_material_id)
     OR EXISTS (SELECT 1 FROM public.movimentacoes WHERE material_id = v_material_id)
  THEN
    RAISE EXCEPTION 'ABORTADO: há vínculos com chamados ou movimentações.';
  END IF;

  DELETE FROM public.estoques
   WHERE id = v_estoque_id AND material_id = v_material_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'ABORTADO: quantidade inesperada de estoques excluídos: %', v_rows;
  END IF;

  DELETE FROM public.materiais
   WHERE id = v_material_id
     AND nome = 'TESTE V18 MASTER 29102026 - NAO UTILIZAR'
     AND consorcio_id IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'ABORTADO: quantidade inesperada de materiais excluídos: %', v_rows;
  END IF;

  RAISE NOTICE 'LIMPEZA EFETUADA: 1 estoque e 1 material de teste.';
END;
$$;
COMMIT;

-- ATENÇÃO: verificar backup e aprovar explicitamente antes de aplicar.
-- Após aplicação, repetir 00_diagnostico_integridade_estoque_somente_leitura.sql.
