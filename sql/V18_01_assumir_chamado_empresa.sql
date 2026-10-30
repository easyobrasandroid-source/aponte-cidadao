-- APONTE CIDADÃO V18 — MIGRAÇÃO OPCIONAL: ASSUMIR CHAMADO LIVRE
-- Preparada em 2026-10-30. NÃO é aplicada por commit no GitHub.
-- Instalar no Supabase SQL Editor APENAS depois de revisar e confirmar o
-- esquema/policies atuais. Nenhuma linha existente é modificada aqui.
--
-- Regras: usuário autenticado com perfil 'empresa' e empresa ativa;
-- chamado sem empresa, com status Recebido ou Em programação;
-- empresa atende a cidade e pertence ao mesmo consórcio.
-- UPDATE atômico evita que duas empresas assumam o mesmo chamado.
-- Após assumir, status continua o mesmo e segue fluxo operacional já existente.

BEGIN;

-- Acrescenta exclusivamente a possibilidade de UPDATE da linha livre:
-- preserva a policy atual de UPDATE para os demais perfis.
DROP POLICY IF EXISTS pol_chamados_claim_empresa ON public.chamados;
CREATE POLICY pol_chamados_claim_empresa ON public.chamados
  FOR UPDATE TO authenticated
  USING (
    public.meu_perfil()='empresa'
    AND empresa_id IS NULL
    AND status IN ('Recebido','Em programação')
    AND public.empresa_atende(cidade_id)
    AND EXISTS (SELECT 1 FROM public.empresas e
                 WHERE e.id=public.minha_empresa() AND e.status='ativo')
  )
  WITH CHECK (
    public.meu_perfil()='empresa'
    AND empresa_id=public.minha_empresa()
    AND public.empresa_atende(cidade_id)
    AND EXISTS (SELECT 1 FROM public.empresas e
                 WHERE e.id=public.minha_empresa() AND e.status='ativo')
  );

-- Insere uma exceção estrita no guard de UPDATE já existente.
-- Em vez de sobrescrever o restante das regras (prefeitura, garantia etc.),
-- preserva a definição ativa no banco e insere o ramo uma única vez.
DO $patch$
DECLARE
  v_def text;
  v_target text := '    IF OLD.empresa_id IS DISTINCT FROM public.minha_empresa()';
  v_inject text := $branch$
    -- APONTE_V18_CLAIM_BRANCH: única exceção permitida de empresa_id.
    IF OLD.empresa_id IS NULL
       AND NEW.empresa_id IS NOT DISTINCT FROM public.minha_empresa()
       AND OLD.status IN ('Recebido','Em programação')
       AND public.empresa_atende(OLD.cidade_id)
       AND EXISTS (SELECT 1 FROM public.empresas e
                    WHERE e.id=NEW.empresa_id AND e.status='ativo')
       AND (to_jsonb(NEW) - ARRAY['empresa_id','empresa','updated_at']::text[])
           IS NOT DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['empresa_id','empresa','updated_at']::text[])
    THEN
      RETURN NEW;
    END IF;

$branch$;
BEGIN
  SELECT pg_get_functiondef('public.guard_chamados()'::regprocedure) INTO v_def;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'guard_chamados() inexistente; migração abortada';
  END IF;
  IF position('APONTE_V18_CLAIM_BRANCH' IN v_def)>0 THEN
    RAISE EXCEPTION 'Migração de assunção já aplicada; nenhuma alteração feita';
  END IF;
  IF position(v_target IN v_def)=0 THEN
    RAISE EXCEPTION 'Versão de guard_chamados diferente da V18 esperada; migração abortada sem alterar guard';
  END IF;
  v_def := replace(v_def, v_target, v_inject||v_target);
  EXECUTE v_def;
END
$patch$;

-- SECURITY INVOKER = respeita políticas RLS de UPDATE e INSERT do histórico.
-- A função faz a alteração somente sob sessão autenticada da empresa.
CREATE OR REPLACE FUNCTION public.assumir_chamado_empresa(p_chamado_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_empresa_id uuid;
  v_nome text;
  v_empresa_status text;
  v_id uuid;
  v_protocolo text;
  v_status text;
BEGIN
  SELECT u.empresa_id, u.nome INTO v_empresa_id, v_nome
    FROM public.usuarios u
   WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa' AND u.status='ativo'
   LIMIT 1;

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'SEM_PERMISSAO' USING ERRCODE='P0001';
  END IF;

  SELECT e.status INTO v_empresa_status
    FROM public.empresas e WHERE e.id=v_empresa_id;

  IF COALESCE(v_empresa_status,'') <> 'ativo' THEN
    RAISE EXCEPTION 'EMPRESA_INATIVA' USING ERRCODE='P0001';
  END IF;

  UPDATE public.chamados c
     SET empresa_id=v_empresa_id, updated_at=now()
   WHERE c.id=p_chamado_id
     AND c.empresa_id IS NULL
     AND c.status IN ('Recebido','Em programação')
     AND public.empresa_atende(c.cidade_id)
     AND c.consorcio_id=(SELECT e.consorcio_id FROM public.empresas e WHERE e.id=v_empresa_id)
   RETURNING c.id,c.protocolo,c.status INTO v_id,v_protocolo,v_status;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_INDISPONIVEL_OU_SEM_PERMISSAO' USING ERRCODE='P0001';
  END IF;

  INSERT INTO public.chamado_historico
    (chamado_id,status,mensagem,observacao,usuario_nome,cor)
  VALUES
    (v_id,v_status,'Chamado assumido por empresa executora',
     'Atribuição confirmada em operação atômica.',COALESCE(v_nome,'Empresa'),'#0D7A55');

  RETURN jsonb_build_object(
    'ok',true,'chamado_id',v_id,'protocolo',v_protocolo,'empresa_id',v_empresa_id);
END $$;

REVOKE ALL ON FUNCTION public.assumir_chamado_empresa(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assumir_chamado_empresa(uuid)
  TO authenticated;

COMMIT;

-- PÓS-INSTALAÇÃO: testar com 2 contas de empresas em paralelo, assegurar
-- que apenas uma assume; confirmar status e empresa após F5, e que prefeitura,
-- garantia e empresas de outra cidade/consórcio não conseguem executar.
