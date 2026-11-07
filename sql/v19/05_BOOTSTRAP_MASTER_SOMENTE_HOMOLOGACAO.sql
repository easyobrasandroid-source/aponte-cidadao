-- APONTE CIDADAO V19 / 05 - BOOTSTRAP DE MASTER (SOMENTE HOMOLOGACAO)
-- Execute APENAS no SQL Editor administrativo do projeto Supabase V19.
-- ANTES de executar, substitua O_EMAIL_DE_TESTE_AQUI pelo e-mail exato
-- que voce cadastrou em Authentication > Users. NAO compartilhe senhas.
-- Este script nao cria conta no Auth, nao grava senha e nao toca na V18.
-- Execute apenas UMA VEZ; falha e reverte caso ja exista qualquer Master.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $v19$
DECLARE
  v_email text := lower(trim('O_EMAIL_DE_TESTE_AQUI'));
  v_auth_id uuid;
  v_count integer;
BEGIN
  IF v_email='o_email_de_teste_aqui'
     OR v_email NOT LIKE '%@%.%' THEN
    RAISE EXCEPTION 'Substitua O_EMAIL_DE_TESTE_AQUI pelo e-mail do Auth V19';
  END IF;
  IF EXISTS(SELECT 1 FROM public.usuarios WHERE perfil='master') THEN
    RAISE EXCEPTION 'Master ja existe: bootstrap bloqueado para evitar duplicacao';
  END IF;
  SELECT count(*) INTO v_count
    FROM auth.users
   WHERE lower(email)=v_email;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Esperada 1 conta no Auth para o e-mail fornecido; encontradas %',v_count;
  END IF;
  SELECT id INTO STRICT v_auth_id
    FROM auth.users
   WHERE lower(email)=v_email;
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Conta Auth sem identificador valido';
  END IF;
  IF EXISTS(SELECT 1 FROM public.usuarios
             WHERE auth_user_id=v_auth_id OR lower(email)=v_email) THEN
    RAISE EXCEPTION 'Conta ja vinculada na tabela de usuarios';
  END IF;
  INSERT INTO public.usuarios(auth_user_id,nome,email,perfil,status)
  VALUES(v_auth_id,'Master Homologacao V19',v_email,'master','ativo');
  RAISE NOTICE 'Master de homologacao vinculado com sucesso (ID Auth registrado)';
END $v19$;

COMMIT;

-- Apenas retorno informativo sem exibir email ou identificadores sensiveis:
SELECT perfil,status, (auth_user_id IS NOT NULL) AS vinculado_ao_auth,
       count(*) AS quantidade
FROM public.usuarios
WHERE perfil='master'
GROUP BY perfil,status,(auth_user_id IS NOT NULL);
