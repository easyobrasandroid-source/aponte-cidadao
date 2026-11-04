-- APONTE CIDADAO V19 / SQL 25
-- CHAMADOS DISPONIVEIS E ATRIBUICAO ATOMICA PARA EMPRESAS
-- SOMENTE NO SUPABASE V19 DE HOMOLOGACAO, NUNCA NA V18
-- Pre-requisitos: tabelas da base limpa, Auth, RLS e SQL 17/18.
-- Nao cria/atualiza chamados reais e nao muda policies de SELECT.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

-- Guarda de ambiente e pre-requisitos
DO $check$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios
                 WHERE slug='teste-v19-alfa')
     OR NOT EXISTS (SELECT 1 FROM public.consorcios
                    WHERE slug='teste-v19-beta')
     OR to_regprocedure('public.v19_concluir_garantia(uuid)') IS NULL
  THEN
    RAISE EXCEPTION 'Projeto V19 de homologacao ou etapas anteriores nao confirmados';
  END IF;
END
$check$;

-- Lista SOMENTE chamados ainda nao atribuidos em cidades que a empresa atende.
-- Projecao sem nome/telefone do solicitante.
CREATE OR REPLACE FUNCTION public.v19_listar_disponiveis(
  p_limite integer DEFAULT 100
)
RETURNS TABLE (
  id uuid, protocolo text, cidade text, bairro text,
  tipo text, qtd integer, status text, created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=''
AS $listar$
DECLARE
  v_empresa uuid;
  v_consorcio uuid;
BEGIN
  IF auth.uid() IS NULL
     OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  SELECT u.empresa_id, u.consorcio_id
  INTO v_empresa, v_consorcio
  FROM public.usuarios u
  JOIN public.empresas e ON e.id=u.empresa_id
  WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa'
    AND u.status='ativo' AND e.status='ativo'
    AND e.consorcio_id=u.consorcio_id;

  IF NOT FOUND OR v_empresa IS NULL OR v_consorcio IS NULL THEN
    RAISE EXCEPTION 'EMPRESA_NAO_AUTORIZADA' USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  SELECT ch.id,ch.protocolo,ch.cidade,ch.bairro,
         ch.tipo,ch.qtd,ch.status,ch.created_at
  FROM public.chamados ch
  JOIN public.cidades cid
    ON cid.id=ch.cidade_id
   AND cid.consorcio_id=ch.consorcio_id
   AND cid.status='ativo'
  JOIN public.empresa_cidades ec
    ON ec.cidade_id=cid.id
   AND ec.empresa_id=v_empresa
  WHERE ch.consorcio_id=v_consorcio
    AND ch.empresa_id IS NULL
    AND ch.status IN ('Recebido','Em programação')
  ORDER BY ch.created_at ASC,ch.id ASC
  LIMIT greatest(1,least(coalesce(p_limite,100),200));
END
$listar$;

-- Atribuicao exclusiva e atomica: duas empresas nao podem assumir o mesmo chamado.
-- Cada empresa so pode assumir se estiver habilitada na cidade e no consorcio.
CREATE OR REPLACE FUNCTION public.v19_assumir_chamado(
  p_chamado_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=''
AS $assumir$
DECLARE
  v_empresa uuid;
  v_consorcio uuid;
  v_empresa_nome text;
  v_usuario_nome text;
  v_id uuid;
  v_protocolo text;
  v_status text;
BEGIN
  IF auth.uid() IS NULL
     OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;
  IF p_chamado_id IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_OBRIGATORIO' USING ERRCODE='22023';
  END IF;

  SELECT u.empresa_id,u.consorcio_id,e.nome,u.nome
  INTO v_empresa,v_consorcio,v_empresa_nome,v_usuario_nome
  FROM public.usuarios u
  JOIN public.empresas e
    ON e.id=u.empresa_id AND e.consorcio_id=u.consorcio_id
  WHERE u.auth_user_id=auth.uid() AND u.perfil='empresa'
    AND u.status='ativo' AND e.status='ativo';

  IF NOT FOUND OR v_empresa IS NULL OR v_consorcio IS NULL THEN
    RAISE EXCEPTION 'EMPRESA_NAO_AUTORIZADA' USING ERRCODE='42501';
  END IF;

  -- UPDATE condicional: o primeiro a assumir vence; o segundo nao atualiza.
  UPDATE public.chamados ch
  SET empresa_id=v_empresa,
      empresa=v_empresa_nome,
      updated_at=clock_timestamp()
  WHERE ch.id=p_chamado_id
    AND ch.consorcio_id=v_consorcio
    AND ch.empresa_id IS NULL
    AND ch.status IN ('Recebido','Em programação')
    AND EXISTS (
      SELECT 1
      FROM public.cidades cid
      JOIN public.empresa_cidades ec
        ON ec.cidade_id=cid.id AND ec.empresa_id=v_empresa
      WHERE cid.id=ch.cidade_id
        AND cid.consorcio_id=v_consorcio AND cid.status='ativo'
    )
  RETURNING ch.id,ch.protocolo,ch.status
  INTO v_id,v_protocolo,v_status;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHAMADO_INDISPONIVEL_OU_JA_ATRIBUIDO'
      USING ERRCODE='42501';
  END IF;

  -- O trigger do SQL 17 registra mudanca de status; como aqui nao mudamos
  -- status, registramos explicitamente UMA atribuicao no historico.
  INSERT INTO public.chamado_historico
    (chamado_id,status,mensagem,observacao,usuario_nome)
  VALUES
    (v_id,v_status,'Chamado assumido pela empresa',
     'Empresa executora: '||v_empresa_nome,v_usuario_nome);

  RETURN jsonb_build_object(
    'ok',true,'chamado_id',v_id,'protocolo',v_protocolo,
    'empresa_id',v_empresa
  );
END
$assumir$;

REVOKE ALL ON FUNCTION public.v19_listar_disponiveis(integer)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_assumir_chamado(uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_listar_disponiveis(integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_assumir_chamado(uuid)
  TO authenticated;

-- Escrita direta de chamados e historico continua bloqueada.
REVOKE INSERT,UPDATE,DELETE ON
  public.chamados,public.chamado_historico
FROM anon,authenticated;

COMMIT;

-- Resultado esperado: 5 linhas OK.
SELECT 'RPC listar instalada' AS verificacao,
  CASE WHEN to_regprocedure('public.v19_listar_disponiveis(integer)')
      IS NOT NULL THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'RPC assumir instalada',
  CASE WHEN to_regprocedure('public.v19_assumir_chamado(uuid)')
      IS NOT NULL THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs bloqueadas para anon',
  CASE WHEN NOT has_function_privilege(
         'anon','public.v19_listar_disponiveis(integer)','EXECUTE')
    AND NOT has_function_privilege(
         'anon','public.v19_assumir_chamado(uuid)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs permitidas a authenticated',
  CASE WHEN has_function_privilege(
         'authenticated','public.v19_listar_disponiveis(integer)','EXECUTE')
    AND has_function_privilege(
         'authenticated','public.v19_assumir_chamado(uuid)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'UPDATE direto bloqueado',
  CASE WHEN NOT has_table_privilege(
    'authenticated','public.chamados','UPDATE')
  THEN 'OK' ELSE 'FALHA' END;
