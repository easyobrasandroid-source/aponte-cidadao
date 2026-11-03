-- APONTE CIDADÃO V19 — 06/06
-- Portal configurável por consórcio + RPCs públicas condicionadas à configuração.
-- NÃO APLICAR EM PRODUÇÃO SEM TESTAR NO AMBIENTE DE HOMOLOGAÇÃO.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE TABLE IF NOT EXISTS public.portal_configuracoes (
  consorcio_id uuid PRIMARY KEY REFERENCES public.consorcios(id) ON DELETE CASCADE,
  portal_ativo boolean NOT NULL DEFAULT true,
  abertura_portal_ativo boolean NOT NULL DEFAULT true,
  consulta_protocolo_ativo boolean NOT NULL DEFAULT true,
  gps_obrigatorio boolean NOT NULL DEFAULT false,
  mostrar_empresa boolean NOT NULL DEFAULT false,
  notificacao_whatsapp boolean NOT NULL DEFAULT false,
  telefone_contato text,
  whatsapp_contato text,
  prazo_medio_texto text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.portal_configuracoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_v19_portal_sel ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_sel ON public.portal_configuracoes
  FOR SELECT TO authenticated USING (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
DROP POLICY IF EXISTS pol_v19_portal_ins ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_ins ON public.portal_configuracoes
  FOR INSERT TO authenticated WITH CHECK (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
DROP POLICY IF EXISTS pol_v19_portal_upd ON public.portal_configuracoes;
CREATE POLICY pol_v19_portal_upd ON public.portal_configuracoes
  FOR UPDATE TO authenticated USING (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  ) WITH CHECK (
    public.is_master() OR
    (public.meu_perfil()='consorcio' AND consorcio_id=public.meu_consorcio())
  );
REVOKE ALL ON public.portal_configuracoes FROM anon;
GRANT SELECT,INSERT,UPDATE ON public.portal_configuracoes TO authenticated;

-- Consulta anônima estritamente limitada à configuração pública do portal.
CREATE OR REPLACE FUNCTION public.v19_consultar_portal(p_cidade_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT jsonb_build_object(
    'portal_ativo',coalesce(p.portal_ativo,true),
    'abertura_portal_ativo',coalesce(p.abertura_portal_ativo,true),
    'consulta_protocolo_ativo',coalesce(p.consulta_protocolo_ativo,true),
    'gps_obrigatorio',coalesce(p.gps_obrigatorio,false),
    'mostrar_empresa',coalesce(p.mostrar_empresa,false),
    'telefone_contato',p.telefone_contato,
    'whatsapp_contato',p.whatsapp_contato,
    'prazo_medio_texto',p.prazo_medio_texto,
    'consorcio_nome',co.nome
  )
  FROM public.cidades cid JOIN public.consorcios co ON co.id=cid.consorcio_id
  LEFT JOIN public.portal_configuracoes p ON p.consorcio_id=co.id
  WHERE cid.id=p_cidade_id AND cid.status='ativo'
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.v19_consultar_portal(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v19_consultar_portal(uuid) TO anon,authenticated;

-- A abertura pública NÃO pode ignorar as opções desativadas no painel.
-- Contrato original V18 mantido para não quebrar formulários existentes.
CREATE OR REPLACE FUNCTION public.abrir_chamado_publico(
  p_cidade_id uuid,p_tipo text,p_bairro text DEFAULT NULL,p_endereco text DEFAULT NULL,
  p_referencia text DEFAULT NULL,p_area text DEFAULT 'Urbana',p_qtd int DEFAULT 1,
  p_observacoes text DEFAULT NULL,p_solicitante_nome text DEFAULT NULL,p_solicitante_tel text DEFAULT NULL,
  p_latitude numeric DEFAULT NULL,p_longitude numeric DEFAULT NULL,p_loc_src text DEFAULT 'manual')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_cons uuid;v_cidnome text;v_proto text;v_id uuid;v_area text;v_qtd int;
        v_ativo boolean;v_abertura boolean;v_gps boolean;
BEGIN
  IF p_cidade_id IS NULL THEN RAISE EXCEPTION 'CIDADE_OBRIGATORIA'; END IF;
  IF p_tipo IS NULL OR length(btrim(p_tipo))=0 OR length(p_tipo)>200
  THEN RAISE EXCEPTION 'TIPO_OBRIGATORIO'; END IF;
  SELECT cid.consorcio_id,cid.nome,coalesce(port.portal_ativo,true),
         coalesce(port.abertura_portal_ativo,true),coalesce(port.gps_obrigatorio,false)
    INTO v_cons,v_cidnome,v_ativo,v_abertura,v_gps
    FROM public.cidades cid
    JOIN public.consorcios co ON co.id=cid.consorcio_id AND co.status='ativo'
    LEFT JOIN public.portal_configuracoes port ON port.consorcio_id=cid.consorcio_id
    WHERE cid.id=p_cidade_id AND cid.status='ativo';
  IF NOT FOUND THEN RAISE EXCEPTION 'CIDADE_INEXISTENTE'; END IF;
  IF NOT v_ativo OR NOT v_abertura THEN RAISE EXCEPTION 'PORTAL_ABERTURA_DESATIVADA'; END IF;
  IF v_gps AND (p_latitude IS NULL OR p_longitude IS NULL
     OR p_loc_src IS DISTINCT FROM 'gps_mobile') THEN RAISE EXCEPTION 'GPS_OBRIGATORIO'; END IF;
  IF p_latitude IS NOT NULL AND (p_latitude < -90 OR p_latitude>90)
     OR p_longitude IS NOT NULL AND (p_longitude < -180 OR p_longitude>180)
  THEN RAISE EXCEPTION 'GPS_INVALIDO'; END IF;
  v_area:=CASE WHEN p_area='Rural' THEN 'Rural' ELSE 'Urbana' END;
  v_qtd:=greatest(1,least(coalesce(p_qtd,1),999));
  v_proto:=public.gerar_protocolo(p_cidade_id);
  INSERT INTO public.chamados(
    protocolo,consorcio_id,cidade_id,cidade,bairro,endereco,referencia,
    area,tipo,qtd,observacoes,status,prioridade,origem,solicitante_nome,solicitante_tel,
    latitude,longitude,loc_src)
  VALUES(v_proto,v_cons,p_cidade_id,v_cidnome,nullif(btrim(coalesce(p_bairro,'')),''),
    nullif(btrim(coalesce(p_endereco,'')),''),nullif(btrim(coalesce(p_referencia,'')),''),
    v_area,btrim(p_tipo),v_qtd,nullif(btrim(coalesce(p_observacoes,'')),''),
    'Recebido','Média','Público',nullif(btrim(coalesce(p_solicitante_nome,'')),''),
    nullif(btrim(coalesce(p_solicitante_tel,'')),''),p_latitude,p_longitude,
    CASE WHEN p_loc_src IN ('manual','gps_mobile','address_geocoding')
     THEN p_loc_src ELSE 'manual' END) RETURNING id INTO v_id;
  INSERT INTO public.chamado_historico(chamado_id,status,mensagem,cor,usuario_nome)
    VALUES(v_id,'Recebido','Chamado aberto pelo canal público','#1251A3','Portal público');
  RETURN jsonb_build_object('ok',true,'protocolo',v_proto);
END;
$$;
REVOKE ALL ON FUNCTION public.abrir_chamado_publico(uuid,text,text,text,text,text,int,text,text,text,numeric,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.abrir_chamado_publico(uuid,text,text,text,text,text,int,text,text,text,numeric,numeric,text) TO anon,authenticated;

-- Consulta pública por protocolo segue protegida por chave exata
-- e passa a respeitar a permissão de consulta definida por consórcio.
CREATE OR REPLACE FUNCTION public.consultar_protocolo(p_protocolo text)
RETURNS TABLE(protocolo text,cidade text,tipo text,status text,created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT c.protocolo,c.cidade,c.tipo,c.status,c.created_at
    FROM public.chamados c
    LEFT JOIN public.portal_configuracoes pc ON pc.consorcio_id=c.consorcio_id
  WHERE p_protocolo IS NOT NULL AND length(btrim(p_protocolo))>=6
    AND c.protocolo=btrim(p_protocolo)
    AND coalesce(pc.portal_ativo,true)
    AND coalesce(pc.consulta_protocolo_ativo,true)
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.consultar_protocolo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_protocolo(text) TO anon,authenticated;
COMMIT;
