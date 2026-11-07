-- APONTE CIDADAO V19 / SQL 62 - ABERTURA INTERNA SEGURA COM SLA
-- Aplicar SOMENTE no projeto aponte-cidadao-v19-homologacao.
-- NUNCA executar em V18 ou producao.
-- RPC autentica: Master, Consorcio, Prefeitura e Empresa (somente seu escopo).
-- Garantia e anonimo nao abrem chamados internos.
-- Protocolo, consorcio, empresa atribuida, status e SLA sao calculados NO SERVIDOR.
-- O SLA automatico e instalado antes, pelo SQL61, via trigger BEFORE INSERT.
-- Nao altera nenhum chamado existente, nenhuma regra e nenhuma policy RLS.
-- O portal publico nao e liberado por esta migration.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

DO $v19$
BEGIN
  IF (SELECT count(*) FROM public.consorcios
      WHERE slug IN ('teste-v19-alfa','teste-v19-beta')
        AND status='ativo') <> 2
     OR (SELECT count(*) FROM public.chamados
         WHERE protocolo IN ('V19-TESTE-UI-GARANTIA-ALFA-A-57',
                             'V19-TESTE-UI-GARANTIA-ALFA-B-57')
           AND status='Concluído')<>2
     OR to_regprocedure('public.v19_salvar_sla_padrao(uuid,integer,integer)') IS NULL
     OR to_regprocedure('public.v19_sla_na_abertura()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgrelid='public.chamados'::regclass
         AND tgname='trg_v19_sla_abertura' AND NOT tgisinternal
     )
     OR (SELECT count(*) FROM public.sla_configuracoes s
         JOIN public.consorcios c ON c.id=s.consorcio_id
         WHERE c.slug='teste-v19-alfa'
           AND s.tipo_problema='PADRAO_GERAL'
           AND s.urb_prazo=48 AND s.rur_prazo=120)<>1
  THEN
    RAISE EXCEPTION 'AMBIENTE_V19_OU_SQL61_NAO_CONFIRMADO';
  END IF;

  IF to_regprocedure(
     'public.v19_criar_chamado_interno(uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'SQL62_JA_INSTALADO_NAO_REEXECUTAR';
  END IF;
  IF has_table_privilege('authenticated','public.chamados','INSERT')
     OR has_table_privilege('anon','public.chamados','INSERT')
     OR has_table_privilege('authenticated','public.chamado_historico','INSERT')
  THEN
    RAISE EXCEPTION 'ESCRITA_DIRETA_NAO_ESTA_BLOQUEADA';
  END IF;
END $v19$;

CREATE FUNCTION public.v19_criar_chamado_interno(
  p_cidade_id uuid,
  p_tipo text,
  p_area text DEFAULT 'Urbana',
  p_bairro text DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_qtd integer DEFAULT 1,
  p_observacoes text DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL,
  p_latitude numeric DEFAULT NULL,
  p_longitude numeric DEFAULT NULL,
  p_loc_src text DEFAULT 'manual'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $criar$
DECLARE
  v_perfil text;
  v_usuario_id uuid;
  v_usuario_nome text;
  v_cons_usuario uuid;
  v_cidade_usuario uuid;
  v_empresa_usuario uuid;
  v_cons_cidade uuid;
  v_cidade_nome text;
  v_empresa uuid;
  v_empresa_nome text;
  v_nome text;
  v_proto text;
  v_id uuid;
  v_sla integer;
  v_criado timestamptz;
  v_area text;
  v_loc_src text;
BEGIN
  IF auth.uid() IS NULL OR auth.role() IS DISTINCT FROM 'authenticated' THEN
    RAISE EXCEPTION 'NAO_AUTENTICADO' USING ERRCODE='42501';
  END IF;

  SELECT u.id,u.nome,u.perfil,u.consorcio_id,u.cidade_id,u.empresa_id
    INTO v_usuario_id,v_usuario_nome,v_perfil,
         v_cons_usuario,v_cidade_usuario,v_empresa_usuario
  FROM public.usuarios u
  WHERE u.auth_user_id=auth.uid() AND u.status='ativo'
  LIMIT 1;
  IF v_usuario_id IS NULL
     OR v_perfil NOT IN ('master','consorcio','prefeitura','empresa') THEN
    RAISE EXCEPTION 'PERFIL_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;

  IF p_cidade_id IS NULL THEN
    RAISE EXCEPTION 'CIDADE_OBRIGATORIA' USING ERRCODE='22023';
  END IF;

  -- Cidade e consorcio somente do banco. Nunca aceitar consorcio do cliente.
  SELECT ci.consorcio_id,ci.nome INTO v_cons_cidade,v_cidade_nome
  FROM public.cidades ci
  JOIN public.consorcios co ON co.id=ci.consorcio_id
  WHERE ci.id=p_cidade_id
    AND ci.status='ativo'
    AND co.status='ativo';

  IF v_cons_cidade IS NULL THEN
    RAISE EXCEPTION 'CIDADE_NAO_DISPONIVEL' USING ERRCODE='42501';
  END IF;
  IF v_perfil<>'master' AND v_cons_usuario IS DISTINCT FROM v_cons_cidade THEN
    RAISE EXCEPTION 'CONSORCIO_NAO_AUTORIZADO' USING ERRCODE='42501';
  END IF;
  IF v_perfil='prefeitura' AND v_cidade_usuario IS DISTINCT FROM p_cidade_id THEN
    RAISE EXCEPTION 'PREFEITURA_CIDADE_NAO_AUTORIZADA' USING ERRCODE='42501';
  END IF;
  IF v_perfil='empresa' AND
     (v_empresa_usuario IS NULL OR NOT EXISTS(
       SELECT 1 FROM public.empresa_cidades ec
       JOIN public.empresas e ON e.id=ec.empresa_id
       WHERE ec.cidade_id=p_cidade_id
         AND ec.empresa_id=v_empresa_usuario
         AND e.consorcio_id=v_cons_cidade AND e.status='ativo'
     )) THEN
    RAISE EXCEPTION 'EMPRESA_CIDADE_NAO_AUTORIZADA' USING ERRCODE='42501';
  END IF;

  IF p_tipo IS NULL OR length(btrim(p_tipo)) NOT BETWEEN 2 AND 160
     OR p_area IS NULL OR p_area NOT IN ('Urbana','Rural')
     OR p_qtd IS NULL OR p_qtd NOT BETWEEN 1 AND 999
     OR length(coalesce(p_bairro,''))>160
     OR length(coalesce(p_endereco,''))>300
     OR length(coalesce(p_observacoes,''))>2000
  THEN
    RAISE EXCEPTION 'DADOS_DO_CHAMADO_INVALIDOS' USING ERRCODE='22023';
  END IF;

  IF (p_latitude IS NULL) <> (p_longitude IS NULL)
     OR (p_latitude IS NOT NULL AND (p_latitude < -90 OR p_latitude > 90))
     OR (p_longitude IS NOT NULL AND (p_longitude < -180 OR p_longitude > 180))
  THEN
    RAISE EXCEPTION 'COORDENADAS_INVALIDAS' USING ERRCODE='22023';
  END IF;
  v_loc_src:=coalesce(p_loc_src,'manual');
  IF v_loc_src NOT IN ('manual','gps_mobile','address_geocoding','minimap_confirmed')
  THEN
    RAISE EXCEPTION 'ORIGEM_COORDENADA_INVALIDA' USING ERRCODE='22023';
  END IF;
  v_area:=p_area;

  -- Autoridade da empresa:
  -- Prefeitura nao designa empresa; empresa sempre abre para si mesma.
  -- Gestor/Master podem indicar empresa ativa que atende a cidade.
  IF v_perfil='prefeitura' THEN
    IF p_empresa_id IS NOT NULL THEN
      RAISE EXCEPTION 'PREFEITURA_NAO_ATRIBUI_EMPRESA' USING ERRCODE='42501';
    END IF;
    v_empresa:=NULL;
  ELSIF v_perfil='empresa' THEN
    IF p_empresa_id IS NOT NULL AND p_empresa_id<>v_empresa_usuario THEN
      RAISE EXCEPTION 'EMPRESA_NAO_PODE_ATRIBUIR_OUTRA' USING ERRCODE='42501';
    END IF;
    v_empresa:=v_empresa_usuario;
  ELSE
    v_empresa:=p_empresa_id;
  END IF;

  IF v_empresa IS NOT NULL THEN
    SELECT e.nome INTO v_empresa_nome
    FROM public.empresas e
    WHERE e.id=v_empresa AND e.consorcio_id=v_cons_cidade
      AND e.status='ativo'
      AND EXISTS(
        SELECT 1 FROM public.empresa_cidades ec
        WHERE ec.empresa_id=e.id AND ec.cidade_id=p_cidade_id
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'EMPRESA_NAO_ATENDE_CIDADE' USING ERRCODE='42501';
    END IF;
  END IF;

  -- Protocolo unico pelo servidor: o frontend nunca e autoridade para protocolo.
  -- UUID aleatorio confere colisao desprezivel e UNIQUE do banco como barreira.
  v_proto:='V19I-'||upper(replace(gen_random_uuid()::text,'-',''));

  INSERT INTO public.chamados(
    protocolo,consorcio_id,cidade_id,cidade,bairro,endereco,area,tipo,
    qtd,observacoes,status,prioridade,empresa_id,empresa,origem,
    solicitante_nome,latitude,longitude,loc_src
  )
  VALUES(
    v_proto,v_cons_cidade,p_cidade_id,v_cidade_nome,
    nullif(btrim(coalesce(p_bairro,'')),''),
    nullif(btrim(coalesce(p_endereco,'')),''),
    v_area,btrim(p_tipo),p_qtd,
    nullif(btrim(coalesce(p_observacoes,'')),''),
    'Recebido','Média',v_empresa,v_empresa_nome,'Interno',
    v_usuario_nome,p_latitude,p_longitude,v_loc_src
  )
  RETURNING id,sla_horas,created_at INTO v_id,v_sla,v_criado;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'CHAMADO_NAO_CONFIRMADO';
  END IF;

  -- Historico inicial e parte da MESMA transacao que cria o chamado.
  INSERT INTO public.chamado_historico(
    chamado_id,status,mensagem,observacao,cor,usuario_nome)
  VALUES(
    v_id,'Recebido','Chamado aberto',
    'Abertura interna autenticada',
    '#1251A3',v_usuario_nome
  );

  RETURN jsonb_build_object(
    'ok',true,'id',v_id,'protocolo',v_proto,'cidade_id',p_cidade_id,
    'consorcio_id',v_cons_cidade,'area',v_area,
    'empresa_id',v_empresa,'status','Recebido','sla_horas',v_sla,
    'created_at',v_criado
  );
END;
$criar$;

REVOKE ALL ON FUNCTION public.v19_criar_chamado_interno(
  uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.v19_criar_chamado_interno(
  uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text
) TO authenticated;

-- Nunca permitir gravacao REST direta: manter so RPCs com permissao derivada do JWT.
REVOKE INSERT,UPDATE,DELETE ON public.chamados,public.chamado_historico
FROM anon,authenticated;
COMMIT;

-- Autoteste ESTRUTURAL. Nao tenta simular JWT no SQL Editor.
SELECT 'Ambiente V19 - Alfa e Beta' AS verificacao,
  CASE WHEN (SELECT count(*) FROM public.consorcios
     WHERE slug IN ('teste-v19-alfa','teste-v19-beta'))=2 THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL SELECT 'RPC abertura interna instalada',
  CASE WHEN to_regprocedure('public.v19_criar_chamado_interno(uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text)') IS NOT NULL
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'RPC permitida para authenticated',
  CASE WHEN has_function_privilege('authenticated',
    'public.v19_criar_chamado_interno(uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'RPC negada para anon',
  CASE WHEN NOT has_function_privilege('anon',
    'public.v19_criar_chamado_interno(uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text)','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'INSERT direto continua bloqueado',
  CASE WHEN NOT has_table_privilege('authenticated','public.chamados','INSERT')
    AND NOT has_table_privilege('anon','public.chamados','INSERT') THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Historico inicial protegido',
  CASE WHEN NOT has_table_privilege('authenticated','public.chamado_historico','INSERT')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'SLA automatico BEFORE INSERT preservado',
  CASE WHEN EXISTS(SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='public.chamados'::regclass
    AND t.tgname='trg_v19_sla_abertura' AND NOT t.tgisinternal)
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Proibida execucao anonima da funcao SLA interna',
  CASE WHEN NOT has_function_privilege('anon','public.v19_sla_na_abertura()','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
ORDER BY verificacao;
