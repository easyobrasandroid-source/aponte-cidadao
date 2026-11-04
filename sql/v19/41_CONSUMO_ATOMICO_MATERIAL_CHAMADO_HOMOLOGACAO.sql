-- APONTE CIDADAO V19 / SQL 41
-- CONSUMO ATOMICO DE MATERIAL VINCULADO AO CHAMADO
-- SOMENTE NO PROJETO aponte-cidadao-v19-homologacao
-- Dependencias: SQL 35 (cadastro e movimento de estoque).
-- Nao executa consumo na instalacao, nem altera a V18.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios
                 WHERE slug='teste-v19-alfa')
     OR NOT EXISTS (SELECT 1 FROM public.consorcios
                    WHERE slug='teste-v19-beta')
     OR to_regprocedure(
        'public.v19_movimentar_estoque(uuid,text,numeric,text)') IS NULL
     OR to_regprocedure(
        'public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)') IS NULL
     OR to_regclass('public.chamado_materiais') IS NULL
     OR to_regclass('public.chamado_historico') IS NULL
     OR to_regprocedure(
        'public.consumir_material_chamado(uuid,uuid,numeric)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'SQL41_AMBIENTE_INCORRETO_OU_JA_INSTALADO';
  END IF;
END $pre$;

-- Contrato da API do frontend:
-- consumir_material_chamado(p_chamado_id,p_material_id,p_quantidade)
-- So usuarios ativos com escopo correto podem consumir.
-- Empresa: deve estar atribuida ao chamado e autorizada na cidade.
-- Consorcio: somente o proprio; Master: qualquer consorcio.
-- Nao consome em chamado concluido, em garantia ou ainda nao iniciado.
CREATE FUNCTION public.consumir_material_chamado(
  p_chamado_id uuid,
  p_material_id uuid,
  p_quantidade numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $consume$
DECLARE
  v_usuario_id uuid;
  v_usuario_nome text;
  v_perfil text;
  v_consorcio_usuario uuid;
  v_empresa_usuario uuid;

  v_consorcio_chamado uuid;
  v_cidade_chamado uuid;
  v_empresa_chamado uuid;
  v_status_chamado text;
  v_protocolo text;

  v_material_nome text;
  v_preco numeric;
  v_estoque_id uuid;
  v_saldo numeric;
  v_contratado numeric;
  v_saldo_novo numeric;
  v_total numeric;
  v_item_id uuid;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  IF p_chamado_id IS NULL OR p_material_id IS NULL
     OR p_quantidade IS NULL OR p_quantidade<=0
     OR p_quantidade>9999999999
     OR round(p_quantidade,2)<>p_quantidade THEN
    RAISE EXCEPTION 'PARAMETROS_DE_CONSUMO_INVALIDOS'
      USING ERRCODE='22023';
  END IF;

  SELECT u.id,u.nome,u.perfil,u.consorcio_id,u.empresa_id
    INTO v_usuario_id,v_usuario_nome,v_perfil,
         v_consorcio_usuario,v_empresa_usuario
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid()
    AND u.status='ativo';

  IF NOT FOUND OR v_perfil NOT IN ('master','consorcio','empresa') THEN
    RAISE EXCEPTION 'PERFIL_NAO_AUTORIZADO_PARA_CONSUMO'
      USING ERRCODE='42501';
  END IF;

  -- Lock no chamado primeiro: se ele for concluido ao mesmo tempo,
  -- uma das operacoes deve esperar e revalidar o status.
  SELECT ch.consorcio_id,ch.cidade_id,ch.empresa_id,
         ch.status,ch.protocolo
    INTO v_consorcio_chamado,v_cidade_chamado,v_empresa_chamado,
         v_status_chamado,v_protocolo
  FROM public.chamados ch
  WHERE ch.id=p_chamado_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHAMADO_NAO_DISPONIVEL'
      USING ERRCODE='42501';
  END IF;

  IF v_perfil='consorcio' THEN
    IF v_consorcio_usuario IS DISTINCT FROM v_consorcio_chamado THEN
      RAISE EXCEPTION 'CONSORCIO_NAO_AUTORIZADO_PARA_CONSUMO'
        USING ERRCODE='42501';
    END IF;

  ELSIF v_perfil='empresa' THEN
    IF v_empresa_usuario IS NULL
       OR v_consorcio_usuario IS DISTINCT FROM v_consorcio_chamado
       OR v_empresa_usuario IS DISTINCT FROM v_empresa_chamado
       OR NOT EXISTS(
         SELECT 1
         FROM public.empresas emp
         JOIN public.empresa_cidades ec ON ec.empresa_id=emp.id
         JOIN public.cidades cid ON cid.id=ec.cidade_id
         WHERE emp.id=v_empresa_usuario
           AND emp.consorcio_id=v_consorcio_chamado
           AND emp.status='ativo'
           AND cid.id=v_cidade_chamado
           AND cid.consorcio_id=v_consorcio_chamado
           AND cid.status='ativo'
       ) THEN
      RAISE EXCEPTION 'EMPRESA_NAO_ATRIBUIDA_OU_SEM_CIDADE'
        USING ERRCODE='42501';
    END IF;
  END IF;

  IF v_status_chamado NOT IN (
    'Em programação',
    'Em execução',
    'Aguard. material',
    'Aguardando material'
  ) THEN
    RAISE EXCEPTION 'STATUS_NAO_PERMITE_CONSUMO'
      USING ERRCODE='22023';
  END IF;

  -- Lock na mesma ordem das movimentacoes administrativas:
  -- material -> estoque. Protege contra edicao de preco e saldo em paralelo.
  SELECT m.nome,m.preco_unitario
    INTO v_material_nome,v_preco
  FROM public.materiais m
  WHERE m.id=p_material_id
    AND m.consorcio_id=v_consorcio_chamado
    AND m.status='ativo'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'MATERIAL_DE_OUTRO_CONSORCIO_OU_INATIVO'
      USING ERRCODE='42501';
  END IF;

  SELECT e.id,e.quantidade_disponivel,e.quantidade_contratada
    INTO v_estoque_id,v_saldo,v_contratado
  FROM public.estoques e
  WHERE e.material_id=p_material_id
    AND e.consorcio_id=v_consorcio_chamado
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESTOQUE_NAO_ENCONTRADO' USING ERRCODE='22023';
  END IF;

  IF v_saldo<p_quantidade THEN
    RAISE EXCEPTION 'SALDO_INSUFICIENTE' USING ERRCODE='22023';
  END IF;

  v_saldo_novo:=v_saldo-p_quantidade;
  v_total:=round(p_quantidade*v_preco,2);

  UPDATE public.estoques
     SET quantidade_disponivel=v_saldo_novo,
         updated_at=clock_timestamp()
   WHERE id=v_estoque_id;

  INSERT INTO public.chamado_materiais(
    chamado_id,material_id,quantidade,preco_unitario,total,usuario_nome
  ) VALUES (
    p_chamado_id,p_material_id,p_quantidade,v_preco,v_total,v_usuario_nome
  ) RETURNING id INTO v_item_id;

  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,chamado_id,tipo,quantidade,
    usuario_nome,usuario_id,origem,observacao
  ) VALUES (
    v_consorcio_chamado,p_material_id,p_chamado_id,'consumo',p_quantidade,
    v_usuario_nome,v_usuario_id,'chamado',
    'Consumo vinculado ao protocolo '||v_protocolo
  );

  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,usuario_nome
  ) VALUES (
    p_chamado_id,v_status_chamado,'Material consumido',
    v_material_nome||' x '||p_quantidade,v_usuario_nome
  );

  RETURN jsonb_build_object(
    'ok',true,
    'protocolo',v_protocolo,
    'item_id',v_item_id,
    'material_id',p_material_id,
    'quantidade',p_quantidade,
    'saldo_anterior',v_saldo,
    'novo_saldo',v_saldo_novo,
    'total',v_total,
    'executor_perfil',v_perfil
  );
END;
$consume$;

REVOKE ALL ON FUNCTION
  public.consumir_material_chamado(uuid,uuid,numeric)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
  public.consumir_material_chamado(uuid,uuid,numeric)
  TO authenticated;

REVOKE INSERT,UPDATE,DELETE ON
  public.chamado_materiais,public.movimentacoes,
  public.estoques,public.chamado_historico
FROM anon,authenticated;

COMMIT;

-- DIAGNOSTICO DE INSTALACAO (NAO SUBSTITUI TESTES FUNCIONAIS)
SELECT 'RPC consumo instalada' AS verificacao,
  CASE WHEN to_regprocedure(
    'public.consumir_material_chamado(uuid,uuid,numeric)'
  ) IS NOT NULL THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'Consumo permitido a authenticated',
  CASE WHEN has_function_privilege(
    'authenticated',
    'public.consumir_material_chamado(uuid,uuid,numeric)',
    'EXECUTE'
  ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Consumo bloqueado para anon',
  CASE WHEN NOT has_function_privilege(
    'anon',
    'public.consumir_material_chamado(uuid,uuid,numeric)',
    'EXECUTE'
  ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Escrita direta de consumo bloqueada',
  CASE WHEN NOT has_table_privilege(
    'authenticated','public.chamado_materiais','INSERT'
  ) THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Escrita direta de movimento bloqueada',
  CASE WHEN NOT has_table_privilege(
    'authenticated','public.movimentacoes','INSERT'
  ) THEN 'OK' ELSE 'FALHA' END;
