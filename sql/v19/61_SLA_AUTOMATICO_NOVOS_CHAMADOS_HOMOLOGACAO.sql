-- APONTE CIDADÃO V19 / SQL 61 — SLA AUTOMÁTICO EM NOVOS CHAMADOS
-- SOMENTE PROJETO V19 DE HOMOLOGAÇÃO; NUNCA V18/PRODUÇÃO.
-- Instalacao de trigger BEFORE INSERT, sem criar rotas de abertura novas.
-- Regra de Alfa: 48 h urbano e 120 h rural (2/5 dias corridos).
-- Consorcio sem regra: SLA NULL (nao inventar prazo).
-- Se futuramente existir regra especifica por tipo, ela tem preferencia.
-- NAO ALTERA CHAMADOS ANTIGOS, HISTORICO OU REGRAS CONFIGURADAS.
-- A migration realiza 3 INSERTS DE TESTE em subtransacao revertida:
-- Alfa urbano=48, Alfa rural=120 e Beta sem regra=NULL.
-- Reexecutar este arquivo e proibido; verificar a saida antes de prosseguir.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.consorcios
      WHERE slug IN ('teste-v19-alfa','teste-v19-beta')
        AND status='ativo') <> 2
     OR (SELECT count(*) FROM public.chamados
         WHERE protocolo IN ('V19-TESTE-UI-GARANTIA-ALFA-A-57',
                             'V19-TESTE-UI-GARANTIA-ALFA-B-57')
           AND status='Concluído') <> 2
     OR to_regprocedure(
          'public.v19_salvar_sla_padrao(uuid,integer,integer)') IS NULL
  THEN
    RAISE EXCEPTION 'V19_HOMOLOGACAO_NAO_CONFIRMADA';
  END IF;

  IF (SELECT count(*) FROM public.sla_configuracoes s
      JOIN public.consorcios c ON c.id=s.consorcio_id
      WHERE c.slug='teste-v19-alfa'
        AND s.tipo_problema='PADRAO_GERAL'
        AND s.urb_prazo=48 AND s.rur_prazo=120) <> 1
     OR EXISTS (
       SELECT 1 FROM public.sla_configuracoes s
       JOIN public.consorcios c ON c.id=s.consorcio_id
       WHERE c.slug='teste-v19-beta'
         AND s.tipo_problema='PADRAO_GERAL'
     )
  THEN
    RAISE EXCEPTION 'REGRAS_ALFA_BETA_DIVERGENTES_DO_SQL60';
  END IF;

  IF to_regprocedure('public.v19_sla_na_abertura()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_trigger t
       WHERE t.tgrelid='public.chamados'::regclass
         AND t.tgname='trg_v19_sla_abertura'
         AND NOT t.tgisinternal
     )
  THEN
    RAISE EXCEPTION 'SQL61_JA_INSTALADO_NAO_REEXECUTAR';
  END IF;

  -- SQL60 confirmou apenas o gatilho de historico AFTER UPDATE.
  -- Se uma migracao paralela tiver criado BEFORE INSERT, analisar ordem
  -- e autorizacao antes de instalar SLA.
  IF EXISTS (
      SELECT 1 FROM pg_trigger t
      WHERE t.tgrelid='public.chamados'::regclass
        AND NOT t.tgisinternal
        AND (t.tgtype::integer & 2)=2
        AND (t.tgtype::integer & 4)=4
  ) THEN
    RAISE EXCEPTION 'OUTRO_TRIGGER_BEFORE_INSERT_INSPECIONAR_ANTES';
  END IF;

  IF has_table_privilege('anon','public.chamados','INSERT')
     OR has_table_privilege('authenticated','public.chamados','INSERT')
  THEN
    RAISE EXCEPTION 'INSERCAO_DIRETA_DE_CHAMADOS_NAO_ESTA_BLOQUEADA';
  END IF;
END
$preflight$;

CREATE FUNCTION public.v19_sla_na_abertura()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $sla$
DECLARE
  v_horas integer;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'SLA_TRIGGER_APENAS_INSERT';
  END IF;
  IF NEW.consorcio_id IS NULL
     OR NEW.area NOT IN ('Urbana','Rural') THEN
    RAISE EXCEPTION 'CONSORCIO_OU_AREA_INVALIDA';
  END IF;

  -- Exclusivamente regras do mesmo consorcio.
  -- Regra por tipo de problema tem precedencia sobre PADRAO_GERAL.
  SELECT CASE WHEN NEW.area='Rural' THEN s.rur_prazo ELSE s.urb_prazo END
  INTO v_horas
  FROM public.sla_configuracoes s
  WHERE s.consorcio_id=NEW.consorcio_id
    AND s.tipo_problema IN (NEW.tipo,'PADRAO_GERAL')
    AND CASE WHEN NEW.area='Rural' THEN s.rur_prazo ELSE s.urb_prazo END > 0
  ORDER BY CASE WHEN s.tipo_problema=NEW.tipo THEN 0 ELSE 1 END
  LIMIT 1;

  IF FOUND THEN
    -- Sempre prevalece a regra do servidor: nao confiar em prazo do cliente.
    NEW.sla_horas:=v_horas;
  ELSE
    -- Sem regra neste consorcio, deixar explicitamente nao apuravel.
    NEW.sla_horas:=NULL;
  END IF;

  RETURN NEW;
END;
$sla$;

REVOKE ALL ON FUNCTION public.v19_sla_na_abertura()
  FROM PUBLIC,anon,authenticated;

CREATE TRIGGER trg_v19_sla_abertura
BEFORE INSERT ON public.chamados
FOR EACH ROW
EXECUTE FUNCTION public.v19_sla_na_abertura();

-- Teste com 3 insercoes reais, mas SEM PERSISTIR OS CHAMADOS.
-- O bloco interno e uma subtransacao: a excecao intencional anula
-- todos os INSERTS de teste, mantendo instalado apenas o trigger.
DO $teste$
DECLARE
  v_cons_a uuid;
  v_cons_b uuid;
  v_cidade_a uuid;
  v_cidade_b uuid;
  v_nome_a text;
  v_nome_b text;
  v_urb integer;
  v_rur integer;
  v_beta integer;
BEGIN
  SELECT c.id,ci.id,ci.nome
    INTO v_cons_a,v_cidade_a,v_nome_a
  FROM public.consorcios c
  JOIN public.cidades ci ON ci.consorcio_id=c.id
  WHERE c.slug='teste-v19-alfa' AND ci.status='ativo'
  ORDER BY ci.id LIMIT 1;

  SELECT c.id,ci.id,ci.nome
    INTO v_cons_b,v_cidade_b,v_nome_b
  FROM public.consorcios c
  JOIN public.cidades ci ON ci.consorcio_id=c.id
  WHERE c.slug='teste-v19-beta' AND ci.status='ativo'
  ORDER BY ci.id LIMIT 1;

  IF v_cidade_a IS NULL OR v_cidade_b IS NULL THEN
    RAISE EXCEPTION 'CIDADES_DE_TESTE_NAO_ENCONTRADAS';
  END IF;

  BEGIN
    INSERT INTO public.chamados
      (protocolo,consorcio_id,cidade_id,cidade,area,tipo,qtd,
       origem,sla_horas)
    VALUES
      ('V19-SLA61-URB-'||gen_random_uuid()::text,
       v_cons_a,v_cidade_a,v_nome_a,'Urbana','Teste SQL61',1,
       'Homologacao',999)
    RETURNING sla_horas INTO v_urb;

    INSERT INTO public.chamados
      (protocolo,consorcio_id,cidade_id,cidade,area,tipo,qtd,
       origem,sla_horas)
    VALUES
      ('V19-SLA61-RUR-'||gen_random_uuid()::text,
       v_cons_a,v_cidade_a,v_nome_a,'Rural','Teste SQL61',1,
       'Homologacao',NULL)
    RETURNING sla_horas INTO v_rur;

    INSERT INTO public.chamados
      (protocolo,consorcio_id,cidade_id,cidade,area,tipo,qtd,
       origem,sla_horas)
    VALUES
      ('V19-SLA61-BETA-'||gen_random_uuid()::text,
       v_cons_b,v_cidade_b,v_nome_b,'Urbana','Teste SQL61',1,
       'Homologacao',NULL)
    RETURNING sla_horas INTO v_beta;

    IF v_urb IS DISTINCT FROM 48
       OR v_rur IS DISTINCT FROM 120
       OR v_beta IS NOT NULL THEN
      RAISE EXCEPTION 'SLA61_AUTO_TESTE_FALHOU: % / % / %',
        v_urb,v_rur,v_beta;
    END IF;

    -- Excecao intencional dentro da subtransacao.
    RAISE EXCEPTION 'SLA61_DESCARTAR_FIXTURES_TESTE';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'SLA61_DESCARTAR_FIXTURES_TESTE' THEN
      RAISE;
    END IF;
  END;

  RAISE NOTICE 'SLA61: 3 testes de INSERT aprovados e descartados; nenhum chamado de teste foi mantido';
END
$teste$;

COMMIT;

-- Resultado auditavel. O SELECT so e executado se o bloco de teste
-- concluiu sem falha. Todas as linhas devem estar OK.
SELECT 'Ambiente Alfa e Beta' AS verificacao,
  CASE WHEN (SELECT count(*) FROM public.consorcios
     WHERE slug IN ('teste-v19-alfa','teste-v19-beta'))=2 THEN 'OK' ELSE 'FALHA' END AS resultado
UNION ALL SELECT 'Trigger SLA BEFORE INSERT instalado',
  CASE WHEN EXISTS(SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='public.chamados'::regclass
      AND t.tgname='trg_v19_sla_abertura'
      AND NOT t.tgisinternal
      AND (t.tgtype::integer & 2)=2 AND (t.tgtype::integer & 4)=4)
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Funcao interna nao executavel por anon',
  CASE WHEN NOT has_function_privilege('anon','public.v19_sla_na_abertura()','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Funcao interna nao executavel por authenticated',
  CASE WHEN NOT has_function_privilege('authenticated','public.v19_sla_na_abertura()','EXECUTE')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Insercao direta de chamado negada ao navegador',
  CASE WHEN NOT has_table_privilege('anon','public.chamados','INSERT')
             AND NOT has_table_privilege('authenticated','public.chamados','INSERT')
  THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Autoteste urbano 48h, rural 120h e Beta sem SLA',
  'OK'
UNION ALL SELECT 'Nenhum chamado de teste persistido',
  CASE WHEN NOT EXISTS(
    SELECT 1 FROM public.chamados c WHERE c.protocolo LIKE 'V19-SLA61-%'
  ) THEN 'OK' ELSE 'FALHA' END
UNION ALL SELECT 'Historico automatico preservado',
  CASE WHEN EXISTS(SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='public.chamados'::regclass
      AND t.tgname='trg_v19_historico_chamados' AND NOT t.tgisinternal)
  THEN 'OK' ELSE 'FALHA' END
ORDER BY verificacao;
