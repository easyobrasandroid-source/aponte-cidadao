-- APONTE CIDADÃO V19 — 07
-- Chamada disponível: projeção mínima e atribuição concorrente/atômica.
-- Depende da migration 05 (guard_chamados atualizado) e 04 (RLS).
-- NÃO APLICAR EM PRODUÇÃO SEM HOMOLOGAÇÃO.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.v19_listar_disponiveis(p_limite integer DEFAULT 100)
RETURNS TABLE(
  id uuid,protocolo text,cidade text,bairro text,tipo text,qtd integer,
  status text,created_at timestamptz
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_empresa uuid;v_cons uuid;
BEGIN
  SELECT u.empresa_id,e.consorcio_id INTO v_empresa,v_cons
  FROM public.usuarios u JOIN public.empresas e ON e.id=u.empresa_id
  WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa' AND u.status='ativo'
    AND e.status='ativo' LIMIT 1;
  IF v_empresa IS NULL OR v_cons IS NULL THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  RETURN QUERY
    SELECT c.id,c.protocolo,c.cidade,c.bairro,c.tipo,c.qtd,c.status,c.created_at
    FROM public.chamados c
    JOIN public.empresa_cidades ec ON ec.cidade_id=c.cidade_id AND ec.empresa_id=v_empresa
    WHERE c.consorcio_id=v_cons
      AND c.empresa_id IS NULL
      AND c.status IN ('Recebido','Em programação')
    ORDER BY c.created_at ASC,c.id ASC
    LIMIT greatest(1,least(coalesce(p_limite,100),200));
END;
$$;

CREATE OR REPLACE FUNCTION public.v19_assumir_chamado(p_chamado_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user uuid;v_nome text;v_empresa uuid;v_cons uuid;v_empnome text;
        v_chamado uuid;v_protocolo text;
BEGIN
  SELECT u.id,u.nome,u.empresa_id,e.consorcio_id,e.nome
    INTO v_user,v_nome,v_empresa,v_cons,v_empnome
    FROM public.usuarios u JOIN public.empresas e ON e.id=u.empresa_id
    WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa' AND u.status='ativo'
      AND e.status='ativo' LIMIT 1;
  IF v_user IS NULL OR v_empresa IS NULL OR v_cons IS NULL
  THEN RAISE EXCEPTION 'SEM_PERMISSAO'; END IF;
  IF p_chamado_id IS NULL THEN RAISE EXCEPTION 'CHAMADO_OBRIGATORIO'; END IF;

  -- UPDATE atômico: só uma transação consegue sair de empresa_id NULL.
  UPDATE public.chamados c
    SET empresa_id=v_empresa,empresa=v_empnome,updated_at=now()
  WHERE c.id=p_chamado_id
    AND c.empresa_id IS NULL
    AND c.consorcio_id=v_cons
    AND c.status IN ('Recebido','Em programação')
    AND EXISTS (
      SELECT 1 FROM public.empresa_cidades ec
        JOIN public.cidades cid ON cid.id=ec.cidade_id
      WHERE ec.empresa_id=v_empresa AND ec.cidade_id=c.cidade_id
        AND cid.consorcio_id=v_cons AND cid.status='ativo'
    )
  RETURNING c.id,c.protocolo INTO v_chamado,v_protocolo;
  IF v_chamado IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_INDISPONIVEL_OU_JA_ATRIBUIDO';
  END IF;

  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,cor,usuario_nome)
  VALUES(v_chamado,'Recebido','Chamado assumido pela empresa',
     'Executor: '||v_empnome,'#1251A3',v_nome);
  RETURN jsonb_build_object('ok',true,'protocolo',v_protocolo,'chamado_id',v_chamado);
END;
$$;
REVOKE ALL ON FUNCTION public.v19_listar_disponiveis(integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_assumir_chamado(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_listar_disponiveis(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_assumir_chamado(uuid) TO authenticated;
COMMIT;
