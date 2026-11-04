-- APONTE CIDADAO V19 — SQL 35
-- FASE 1: CADASTRO E MOVIMENTACAO MANUAL DE ESTOQUE
-- APENAS NO PROJETO aponte-cidadao-v19-homologacao.
-- Prerequisitos: SQLs 01-03 da base limpa, Auth e usuarios ativos.
-- Nao executar os SQLs antigos "03_rpc_estoque_stage1" ou
-- "03_rpc_estoque_transacional_NAO_APLICAR" em conjunto com este arquivo.
-- Nao cria materiais de teste nem modifica saldos existentes no momento da instalacao.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-alfa')
     OR NOT EXISTS (SELECT 1 FROM public.consorcios WHERE slug='teste-v19-beta')
     OR to_regclass('public.materiais') IS NULL
     OR to_regclass('public.estoques') IS NULL
     OR to_regclass('public.movimentacoes') IS NULL
     OR EXISTS (SELECT 1 FROM public.materiais LIMIT 1)
     OR EXISTS (SELECT 1 FROM public.estoques LIMIT 1)
     OR EXISTS (SELECT 1 FROM public.movimentacoes LIMIT 1)
     OR to_regprocedure('public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)') IS NOT NULL
     OR to_regprocedure('public.v19_movimentar_estoque(uuid,text,numeric,text)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'SQL35_PRECONDIÇÕES_NAO_ATENDIDAS_OU_JA_INSTALADO';
  END IF;
END;
$guard$;

-- Contrato do frontend V19: retorno JSON com ok=true e material_id.
-- A transacao cobre cadastro + saldo + movimento + auditoria.
CREATE FUNCTION public.v19_salvar_material(
  p_material_id uuid,
  p_consorcio_id uuid,
  p_nome text,
  p_unidade text,
  p_estoque_minimo numeric,
  p_preco_unitario numeric,
  p_quantidade_contratada numeric,
  p_quantidade_disponivel numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $salvar$
DECLARE
  v_uid uuid;
  v_nome_usuario text;
  v_perfil text;
  v_consorcio_usuario uuid;
  v_consorcio_material uuid;
  v_material_id uuid;
  v_estoque_id uuid;
  v_saldo_anterior numeric := 0;
  v_contratado_anterior numeric := 0;
  v_delta numeric := 0;
  v_criado boolean := false;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  SELECT u.id,u.nome,u.perfil,u.consorcio_id
    INTO v_uid,v_nome_usuario,v_perfil,v_consorcio_usuario
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';

  IF NOT FOUND OR v_perfil NOT IN ('master','consorcio') THEN
    RAISE EXCEPTION 'PERFIL_SEM_PERMISSAO_DE_ESTOQUE'
      USING ERRCODE='42501';
  END IF;

  IF p_consorcio_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.consorcios c
       WHERE c.id=p_consorcio_id AND c.status='ativo'
     )
     OR (v_perfil='consorcio'
         AND v_consorcio_usuario IS DISTINCT FROM p_consorcio_id) THEN
    RAISE EXCEPTION 'CONSORCIO_NAO_AUTORIZADO'
      USING ERRCODE='42501';
  END IF;

  IF p_nome IS NULL OR length(btrim(p_nome)) NOT BETWEEN 1 AND 250
     OR p_estoque_minimo IS NULL OR p_estoque_minimo<0
     OR p_preco_unitario IS NULL OR p_preco_unitario<0
     OR p_quantidade_contratada IS NULL OR p_quantidade_contratada<0
     OR p_quantidade_disponivel IS NULL OR p_quantidade_disponivel<0
     OR p_quantidade_disponivel>p_quantidade_contratada
     OR p_quantidade_contratada>9999999999
     OR p_estoque_minimo>9999999999
     OR p_preco_unitario>9999999999
     OR round(p_quantidade_contratada,2)<>p_quantidade_contratada
     OR round(p_quantidade_disponivel,2)<>p_quantidade_disponivel
     OR round(p_estoque_minimo,2)<>p_estoque_minimo
     OR round(p_preco_unitario,2)<>p_preco_unitario
     OR p_unidade IS NULL OR length(btrim(p_unidade)) NOT BETWEEN 1 AND 30
  THEN
    RAISE EXCEPTION 'DADOS_DE_MATERIAL_INVALIDOS'
      USING ERRCODE='22023';
  END IF;

  IF p_material_id IS NULL THEN
    INSERT INTO public.materiais(
      consorcio_id,nome,unidade,estoque_minimo,preco_unitario,status
    ) VALUES (
      p_consorcio_id,btrim(p_nome),btrim(p_unidade),
      p_estoque_minimo,p_preco_unitario,'ativo'
    )
    RETURNING id INTO v_material_id;
    v_criado := true;
  ELSE
    SELECT m.consorcio_id INTO v_consorcio_material
    FROM public.materiais m
    WHERE m.id=p_material_id AND m.status='ativo'
    FOR UPDATE;

    IF NOT FOUND OR v_consorcio_material IS DISTINCT FROM p_consorcio_id THEN
      RAISE EXCEPTION 'MATERIAL_DE_OUTRO_CONSORCIO_OU_INEXISTENTE'
        USING ERRCODE='42501';
    END IF;

    v_material_id := p_material_id;
    UPDATE public.materiais
       SET nome=btrim(p_nome),
           unidade=btrim(p_unidade),
           estoque_minimo=p_estoque_minimo,
           preco_unitario=p_preco_unitario
    WHERE id=v_material_id;
  END IF;

  SELECT e.id,e.quantidade_contratada,e.quantidade_disponivel
    INTO v_estoque_id,v_contratado_anterior,v_saldo_anterior
  FROM public.estoques e
  WHERE e.material_id=v_material_id
    AND e.consorcio_id=p_consorcio_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_criado THEN
      RAISE EXCEPTION 'ESTOQUE_INCONSISTENTE_COM_MATERIAL_NOVO';
    END IF;

    v_delta := p_quantidade_disponivel-v_saldo_anterior;
    UPDATE public.estoques
       SET quantidade_contratada=p_quantidade_contratada,
           quantidade_disponivel=p_quantidade_disponivel,
           updated_at=clock_timestamp()
    WHERE id=v_estoque_id;
  ELSE
    -- A FK composta garante material e consorcio consistentes.
    IF NOT v_criado THEN
      RAISE EXCEPTION 'MATERIAL_EXISTENTE_SEM_LINHA_DE_ESTOQUE';
    END IF;

    INSERT INTO public.estoques(
      material_id,consorcio_id,quantidade_contratada,quantidade_disponivel
    ) VALUES (
      v_material_id,p_consorcio_id,
      p_quantidade_contratada,p_quantidade_disponivel
    );

    v_delta := p_quantidade_disponivel;
  END IF;

  IF v_delta<>0 THEN
    INSERT INTO public.movimentacoes(
      consorcio_id,material_id,tipo,quantidade,
      usuario_nome,usuario_id,origem,observacao
    )
    VALUES (
      p_consorcio_id,v_material_id,
      CASE WHEN v_delta>0 THEN 'entrada' ELSE 'saida' END,
      abs(v_delta),v_nome_usuario,v_uid,
      CASE WHEN v_criado THEN 'cadastro_inicial' ELSE 'ajuste_catalogo' END,
      'Saldo anterior: '||coalesce(v_saldo_anterior,0)||
      '; novo saldo: '||p_quantidade_disponivel||
      '; contratado anterior: '||coalesce(v_contratado_anterior,0)||
      '; novo contratado: '||p_quantidade_contratada
    );
  END IF;

  INSERT INTO public.auditoria(consorcio_id,usuario_responsavel,acao,detalhes)
  VALUES (
    p_consorcio_id,v_nome_usuario,
    CASE WHEN v_criado THEN 'v19_material_criado' ELSE 'v19_material_editado' END,
    'Material '||v_material_id||
    '; quantidade contratada: '||p_quantidade_contratada||
    '; quantidade disponivel: '||p_quantidade_disponivel
  );

  RETURN jsonb_build_object(
    'ok',true,'material_id',v_material_id,
    'saldo',p_quantidade_disponivel,
    'contratado',p_quantidade_contratada,
    'movimento_gerado',v_delta<>0
  );
END;
$salvar$;

-- Entrada e saida manual atômicas (saldo e historico na mesma transacao).
-- Entrada aumenta disponivel E contratado; saida so diminui disponivel.
CREATE FUNCTION public.v19_movimentar_estoque(
  p_material_id uuid,
  p_tipo text,
  p_quantidade numeric,
  p_observacao text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $mov$
DECLARE
  v_uid uuid;
  v_nome_usuario text;
  v_perfil text;
  v_consorcio_usuario uuid;
  v_consorcio_material uuid;
  v_estoque_id uuid;
  v_saldo numeric;
  v_contratado numeric;
  v_saldo_novo numeric;
  v_contratado_novo numeric;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  IF p_material_id IS NULL OR p_tipo IS NULL
     OR p_tipo NOT IN ('entrada','saida')
     OR p_quantidade IS NULL OR p_quantidade<=0
     OR p_quantidade>9999999999
     OR round(p_quantidade,2)<>p_quantidade THEN
    RAISE EXCEPTION 'MOVIMENTACAO_INVALIDA' USING ERRCODE='22023';
  END IF;

  SELECT u.id,u.nome,u.perfil,u.consorcio_id
    INTO v_uid,v_nome_usuario,v_perfil,v_consorcio_usuario
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo';

  IF NOT FOUND OR v_perfil NOT IN ('master','consorcio') THEN
    RAISE EXCEPTION 'PERFIL_SEM_PERMISSAO_DE_ESTOQUE'
      USING ERRCODE='42501';
  END IF;

  -- Trava o material primeiro, mesma ordem usada no cadastro/edicao.
  SELECT m.consorcio_id INTO v_consorcio_material
  FROM public.materiais m
  JOIN public.consorcios c
    ON c.id=m.consorcio_id AND c.status='ativo'
  WHERE m.id=p_material_id AND m.status='ativo'
  FOR UPDATE OF m;

  IF NOT FOUND
     OR (v_perfil='consorcio'
         AND v_consorcio_usuario IS DISTINCT FROM v_consorcio_material) THEN
    RAISE EXCEPTION 'MATERIAL_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;

  SELECT e.id,e.quantidade_disponivel,e.quantidade_contratada
    INTO v_estoque_id,v_saldo,v_contratado
  FROM public.estoques e
  WHERE e.material_id=p_material_id
    AND e.consorcio_id=v_consorcio_material
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESTOQUE_NAO_ENCONTRADO';
  END IF;

  v_saldo_novo:=v_saldo+
    CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE -p_quantidade END;
  v_contratado_novo:=v_contratado+
    CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE 0 END;

  IF v_saldo_novo<0 THEN
    RAISE EXCEPTION 'SALDO_INSUFICIENTE' USING ERRCODE='22023';
  END IF;
  IF v_saldo_novo>v_contratado_novo
     OR v_contratado_novo>9999999999 THEN
    RAISE EXCEPTION 'LIMITE_DE_ESTOQUE_INVALIDO'
      USING ERRCODE='22023';
  END IF;

  UPDATE public.estoques
     SET quantidade_disponivel=v_saldo_novo,
         quantidade_contratada=v_contratado_novo,
         updated_at=clock_timestamp()
   WHERE id=v_estoque_id;

  INSERT INTO public.movimentacoes(
    consorcio_id,material_id,tipo,quantidade,
    usuario_nome,usuario_id,origem,observacao
  )
  VALUES(
    v_consorcio_material,p_material_id,p_tipo,p_quantidade,
    v_nome_usuario,v_uid,'ajuste_manual',left(btrim(coalesce(p_observacao,'')),500)
  );

  RETURN jsonb_build_object(
    'ok',true,'material_id',p_material_id,
    'novo_saldo',v_saldo_novo,
    'contratado',v_contratado_novo
  );
END;
$mov$;

REVOKE ALL ON FUNCTION public.v19_salvar_material(
  uuid,uuid,text,text,numeric,numeric,numeric,numeric
) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_movimentar_estoque(
  uuid,text,numeric,text
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_salvar_material(
  uuid,uuid,text,text,numeric,numeric,numeric,numeric
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_movimentar_estoque(
  uuid,text,numeric,text
) TO authenticated;

-- A fonte de verdade continua sendo somente RPC no banco.
REVOKE INSERT,UPDATE,DELETE
ON public.materiais,public.estoques,public.movimentacoes
FROM anon,authenticated;

COMMIT;

SELECT 'RPC cadastro instalada' AS verificacao,
 CASE WHEN to_regprocedure(
 'public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)'
 ) IS NOT NULL THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL
SELECT 'RPC movimentacao instalada',
 CASE WHEN to_regprocedure(
 'public.v19_movimentar_estoque(uuid,text,numeric,text)'
 ) IS NOT NULL THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs disponiveis para authenticated',
 CASE WHEN has_function_privilege('authenticated',
 'public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)',
 'EXECUTE')
 AND has_function_privilege('authenticated',
 'public.v19_movimentar_estoque(uuid,text,numeric,text)','EXECUTE')
 THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'RPCs bloqueadas para anon',
 CASE WHEN NOT has_function_privilege('anon',
 'public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)',
 'EXECUTE')
 AND NOT has_function_privilege('anon',
 'public.v19_movimentar_estoque(uuid,text,numeric,text)','EXECUTE')
 THEN 'OK' ELSE 'FALHA' END
UNION ALL
SELECT 'Escrita direta de estoque bloqueada',
 CASE WHEN NOT has_table_privilege('authenticated','public.materiais','UPDATE')
 AND NOT has_table_privilege('authenticated','public.estoques','UPDATE')
 AND NOT has_table_privilege('authenticated','public.movimentacoes','INSERT')
 THEN 'OK' ELSE 'FALHA' END;
