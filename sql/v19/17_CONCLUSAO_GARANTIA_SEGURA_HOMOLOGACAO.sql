-- APONTE CIDADAO V19 / SQL 17
-- CONCLUSAO SEGURA DA GARANTIA LED + HISTORICO AUTOMATICO
-- EXECUTAR SOMENTE NO PROJETO aponte-cidadao-v19-homologacao.
-- Nao executar o pacote antigo 08 da V18/V19.
-- Este script NAO concede UPDATE direto a usuarios.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Protecao: exige a massa de teste exclusiva da nova homologacao.
DO $verificar$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.consorcios
    WHERE slug = 'teste-v19-alfa'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.chamados
    WHERE protocolo = 'V19-TESTE-GARANTIA-ALFA-1'
      AND status = 'Aguardando Garantia LED'
      AND garantia_tipo = 'LED'
  ) THEN
    RAISE EXCEPTION 'AMBIENTE_INCORRETO_OU_DADOS_DE_TESTE_AUSENTES';
  END IF;
END
$verificar$;

-- Esta funcao e chamada exclusivamente pelo gatilho do banco.
-- Ela registra transicoes de status e alteracoes de observacoes.
CREATE OR REPLACE FUNCTION public.v19_registrar_historico_chamado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $historico$
DECLARE
  v_nome text;
  v_descricao text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.observacoes IS NOT DISTINCT FROM OLD.observacoes THEN
    RETURN NEW;
  END IF;

  SELECT u.nome INTO v_nome
  FROM public.usuarios u
  WHERE u.auth_user_id = auth.uid() AND u.status = 'ativo'
  LIMIT 1;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_descricao := coalesce(OLD.status, '(sem status)')
                    || ' -> ' || coalesce(NEW.status, '(sem status)');
  ELSE
    v_descricao := 'Observacoes alteradas';
  END IF;

  INSERT INTO public.chamado_historico
    (chamado_id, status, mensagem, observacao, usuario_nome)
  VALUES
    (NEW.id, NEW.status,
     CASE WHEN NEW.status IS DISTINCT FROM OLD.status
          THEN 'Status alterado'
          ELSE 'Observacoes alteradas'
     END,
     v_descricao,
     coalesce(v_nome, 'Sistema'));

  RETURN NEW;
END;
$historico$;

DROP TRIGGER IF EXISTS trg_v19_historico_chamados ON public.chamados;
CREATE TRIGGER trg_v19_historico_chamados
AFTER UPDATE OF status, observacoes ON public.chamados
FOR EACH ROW
WHEN (
  OLD.status IS DISTINCT FROM NEW.status OR
  OLD.observacoes IS DISTINCT FROM NEW.observacoes
)
EXECUTE FUNCTION public.v19_registrar_historico_chamado();

-- Nunca permitir ao navegador executar a funcao interna do trigger.
REVOKE ALL ON FUNCTION public.v19_registrar_historico_chamado()
FROM PUBLIC, anon, authenticated;

-- Unica operacao de conclusao autorizada ao tecnico Garantia.
-- Roda atomicamente, bloqueia concorrencia e grava historico via trigger.
CREATE OR REPLACE FUNCTION public.v19_concluir_garantia(p_chamado_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $conclusao$
DECLARE
  v_consorcio uuid;
  v_nome text;
  v_status text;
  v_garantia text;
  v_criacao timestamptz;
  v_protocolo text;
  v_agora timestamptz;
BEGIN
  -- O Auth real, e nao um id enviado pela interface, determina o usuario.
  IF auth.uid() IS NULL
     OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE = '42501';
  END IF;

  IF p_chamado_id IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_OBRIGATORIO';
  END IF;

  SELECT u.consorcio_id, u.nome
    INTO v_consorcio, v_nome
  FROM public.usuarios u
  WHERE u.auth_user_id = auth.uid()
    AND u.status = 'ativo'
    AND u.perfil = 'garantia'
    AND u.consorcio_id IS NOT NULL
    AND u.empresa_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERFIL_GARANTIA_NAO_AUTORIZADO'
      USING ERRCODE = '42501';
  END IF;

  -- O SELECT FOR UPDATE impede duas conclusoes simultaneas.
  -- A ausencia inclui chamados inexistentes e de outro consorcio.
  SELECT c.status, c.garantia_tipo, c.created_at, c.protocolo
    INTO v_status, v_garantia, v_criacao, v_protocolo
  FROM public.chamados c
  WHERE c.id = p_chamado_id
    AND c.consorcio_id = v_consorcio
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHAMADO_NAO_DISPONIVEL'
      USING ERRCODE = '42501';
  END IF;

  IF v_status IS DISTINCT FROM 'Aguardando Garantia LED'
     OR nullif(btrim(v_garantia), '') IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_NAO_ELEGIVEL_OU_JA_CONCLUIDO';
  END IF;

  v_agora := clock_timestamp();
  IF v_agora < v_criacao THEN
    RAISE EXCEPTION 'DATA_DE_CONCLUSAO_INVALIDA';
  END IF;

  UPDATE public.chamados
     SET status = 'Concluído',
         completed_at = v_agora,
         garantia_dt = v_agora,
         garantia_user = v_nome,
         updated_at = v_agora
   WHERE id = p_chamado_id
     AND consorcio_id = v_consorcio
     AND status = 'Aguardando Garantia LED';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CONCLUSAO_NAO_CONFIRMADA';
  END IF;

  -- A mudanca de status aciona o trigger e registra o historico.
  RETURN jsonb_build_object(
    'ok', true,
    'protocolo', v_protocolo,
    'status', 'Concluído',
    'completed_at', v_agora
  );
END;
$conclusao$;

-- Permissoes minimas: RPC acessivel apenas a autenticados.
REVOKE ALL ON FUNCTION public.v19_concluir_garantia(uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.v19_concluir_garantia(uuid)
TO authenticated;

-- Manter escrita direta bloqueada; o historico deve ser confiavel.
REVOKE INSERT, UPDATE, DELETE ON
  public.chamados, public.chamado_historico
FROM anon, authenticated;
COMMIT;

-- DIAGNOSTICO: retorno esperado = OK nas 5 linhas.
SELECT 'RPC de conclusao instalada' AS verificacao,
       CASE WHEN to_regprocedure('public.v19_concluir_garantia(uuid)')
                 IS NOT NULL THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'Trigger de historico instalado',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.chamados'::regclass
           AND tgname = 'trg_v19_historico_chamados'
           AND NOT tgisinternal
       ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPC disponivel para authenticated',
       CASE WHEN has_function_privilege(
         'authenticated', 'public.v19_concluir_garantia(uuid)', 'EXECUTE'
       ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPC bloqueada para anon',
       CASE WHEN NOT has_function_privilege(
         'anon', 'public.v19_concluir_garantia(uuid)', 'EXECUTE'
       ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'UPDATE direto bloqueado',
       CASE WHEN NOT has_table_privilege(
         'authenticated', 'public.chamados', 'UPDATE'
       ) THEN 'OK' ELSE 'FALHA' END;
