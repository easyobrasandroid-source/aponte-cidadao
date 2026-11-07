-- Aponte Cidadão V19 — STAGE 1: RPCs de estoque, SEM revogar RLS existente
-- MIGRATION DE HOMOLOGAÇÃO. NÃO EXECUTAR NA PRODUÇÃO ANTES DE TESTES.
-- Cada função executa as alterações em uma única transação do PostgreSQL.
-- Pré-requisito: tabelas public.usuarios, materiais, estoques, movimentacoes existentes.
-- Etapa 2 (separada): remover DML direto depois que todos os clientes migrarem.

CREATE OR REPLACE FUNCTION public.v19_salvar_material(
  p_material_id uuid,
  p_consorcio_id uuid,
  p_nome text,
  p_unidade text,
  p_estoque_minimo numeric,
  p_preco_unitario numeric,
  p_quantidade_contratada numeric,
  p_quantidade_disponivel numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user public.usuarios%ROWTYPE;
  v_consorcio uuid;
  v_material uuid;
  v_antigo public.estoques%ROWTYPE;
  v_existente boolean;
  v_delta numeric;
BEGIN
  SELECT * INTO v_user FROM public.usuarios
   WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF NOT FOUND OR v_user.perfil NOT IN ('master','consorcio') THEN
    RAISE EXCEPTION 'Sem permissão para cadastrar ou editar material' USING ERRCODE='42501';
  END IF;
  IF nullif(btrim(p_nome),'') IS NULL OR length(p_nome)>250
     OR p_estoque_minimo IS NULL OR p_estoque_minimo<0
     OR p_preco_unitario IS NULL OR p_preco_unitario<0
     OR p_quantidade_contratada IS NULL OR p_quantidade_contratada<0
     OR p_quantidade_disponivel IS NULL OR p_quantidade_disponivel<0
     OR p_quantidade_disponivel>p_quantidade_contratada
  THEN RAISE EXCEPTION 'Dados inválidos para material/estoque'; END IF;
  IF p_material_id IS NULL THEN
    v_consorcio := CASE WHEN v_user.perfil='master' THEN p_consorcio_id ELSE v_user.consorcio_id END;
  ELSE
    SELECT consorcio_id INTO v_consorcio
    FROM public.materiais WHERE id=p_material_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Material não encontrado'; END IF;
    IF p_consorcio_id IS NOT NULL AND p_consorcio_id<>v_consorcio THEN
      RAISE EXCEPTION 'Não é permitido transferir material entre consórcios';
    END IF;
  END IF;
  IF v_consorcio IS NULL OR NOT EXISTS (SELECT 1 FROM public.consorcios WHERE id=v_consorcio) THEN
    RAISE EXCEPTION 'Selecione um consórcio válido';
  END IF;
  IF v_user.perfil='consorcio' AND v_consorcio IS DISTINCT FROM v_user.consorcio_id THEN
    RAISE EXCEPTION 'Material de outro consórcio' USING ERRCODE='42501';
  END IF;
  IF p_material_id IS NULL THEN
    INSERT INTO public.materiais(consorcio_id,nome,unidade,estoque_minimo,preco_unitario,status)
    VALUES(v_consorcio,btrim(p_nome),coalesce(nullif(btrim(p_unidade),''),'Un.'),
           p_estoque_minimo,p_preco_unitario,'ativo')
    RETURNING id INTO v_material;
  ELSE
    v_material:=p_material_id;
    UPDATE public.materiais SET nome=btrim(p_nome),
      unidade=coalesce(nullif(btrim(p_unidade),''),'Un.'),
      estoque_minimo=p_estoque_minimo, preco_unitario=p_preco_unitario
    WHERE id=v_material;
  END IF;

  IF (SELECT count(*) FROM public.estoques WHERE material_id=v_material) > 1 THEN
    RAISE EXCEPTION 'Estoque duplicado; operação cancelada';
  END IF;
  SELECT * INTO v_antigo FROM public.estoques WHERE material_id=v_material FOR UPDATE;
  v_existente:=FOUND;
  IF v_existente THEN
    IF v_antigo.consorcio_id IS DISTINCT FROM v_consorcio THEN
      RAISE EXCEPTION 'Consórcio do estoque incompatível';
    END IF;
    v_delta:=p_quantidade_disponivel-coalesce(v_antigo.quantidade_disponivel,0);
    UPDATE public.estoques SET quantidade_contratada=p_quantidade_contratada,
      quantidade_disponivel=p_quantidade_disponivel, updated_at=now()
    WHERE id=v_antigo.id;
  ELSE
    v_delta:=p_quantidade_disponivel;
    INSERT INTO public.estoques(material_id,consorcio_id,quantidade_contratada,quantidade_disponivel,updated_at)
    VALUES(v_material,v_consorcio,p_quantidade_contratada,p_quantidade_disponivel,now());
  END IF;
  IF v_delta<>0 THEN
    INSERT INTO public.movimentacoes(consorcio_id,material_id,tipo,quantidade,
      usuario_nome,usuario_id,origem,observacao)
    VALUES(v_consorcio,v_material,CASE WHEN v_delta>0 THEN 'entrada' ELSE 'saida' END,
      abs(v_delta),v_user.nome,v_user.id,'ajuste_catalogo',
      'Ajuste de saldo realizado na edição/cadastro de material');
  END IF;
  RETURN v_material;
END;
$$;

CREATE OR REPLACE FUNCTION public.v19_movimentar_estoque(
  p_material_id uuid,
  p_tipo text,
  p_quantidade numeric,
  p_observacao text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user public.usuarios%ROWTYPE;
  v_mat public.materiais%ROWTYPE;
  v_est public.estoques%ROWTYPE;
  v_novo numeric;
  v_contratado numeric;
BEGIN
  SELECT * INTO v_user FROM public.usuarios
  WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  IF NOT FOUND OR v_user.perfil NOT IN ('master','consorcio') THEN
    RAISE EXCEPTION 'Sem permissão para movimentação manual de estoque' USING ERRCODE='42501';
  END IF;
  IF p_tipo NOT IN ('entrada','saida') OR p_quantidade IS NULL
     OR p_quantidade<=0 OR p_quantidade<>trunc(p_quantidade) THEN
    RAISE EXCEPTION 'Tipo ou quantidade inválida';
  END IF;
  SELECT * INTO v_mat FROM public.materiais WHERE id=p_material_id;
  IF NOT FOUND OR v_mat.consorcio_id IS NULL THEN RAISE EXCEPTION 'Material não encontrado ou sem consórcio'; END IF;
  IF v_user.perfil='consorcio' AND v_user.consorcio_id IS DISTINCT FROM v_mat.consorcio_id THEN
    RAISE EXCEPTION 'Estoque de outro consórcio' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_est FROM public.estoques WHERE material_id=p_material_id FOR UPDATE;
  IF NOT FOUND OR v_est.consorcio_id IS DISTINCT FROM v_mat.consorcio_id THEN
    RAISE EXCEPTION 'Estoque não encontrado ou consórcio divergente';
  END IF;
  IF (SELECT count(*) FROM public.estoques WHERE material_id=p_material_id)>1 THEN
    RAISE EXCEPTION 'Estoque duplicado';
  END IF;
  v_novo:=coalesce(v_est.quantidade_disponivel,0)+
    (CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE -p_quantidade END);
  IF v_novo<0 THEN RAISE EXCEPTION 'Saldo insuficiente'; END IF;
  v_contratado:=coalesce(v_est.quantidade_contratada,0)+
    (CASE WHEN p_tipo='entrada' THEN p_quantidade ELSE 0 END);
  UPDATE public.estoques SET quantidade_disponivel=v_novo,
    quantidade_contratada=v_contratado,updated_at=now() WHERE id=v_est.id;
  INSERT INTO public.movimentacoes(consorcio_id,material_id,tipo,quantidade,
    usuario_nome,usuario_id,origem,observacao)
  VALUES(v_mat.consorcio_id,p_material_id,p_tipo,p_quantidade,
    v_user.nome,v_user.id,'ajuste_manual',nullif(btrim(p_observacao),''));
  RETURN jsonb_build_object('material_id',p_material_id,
    'quantidade_disponivel',v_novo,'quantidade_contratada',v_contratado);
END;
$$;

REVOKE ALL ON FUNCTION public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.v19_movimentar_estoque(uuid,text,numeric,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_salvar_material(uuid,uuid,text,text,numeric,numeric,numeric,numeric)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.v19_movimentar_estoque(uuid,text,numeric,text)
  TO authenticated;
-- FIM STAGE 1. Não revogar acesso direto neste estágio.
