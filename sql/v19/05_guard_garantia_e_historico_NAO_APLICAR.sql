-- APONTE CIDADÃO V19 — 05/05
-- Garante conclusão controlada da Garantia LED; demais guards V18 preservados.
-- Base exata: export dos triggers da produção em 2026-11-03.
-- NÃO APLICAR EM PRODUÇÃO sem ambiente de homologação e regressão.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE OR REPLACE FUNCTION public.guard_chamados()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_cidade_cons uuid; v_empresa_cons uuid; v_usuario_cons uuid; v_perfil text;
BEGIN
  IF NEW.consorcio_id IS NULL OR NEW.cidade_id IS NULL THEN RAISE EXCEPTION 'PROIBIDO: chamado sem consorcio/cidade'; END IF;
  SELECT c.consorcio_id INTO v_cidade_cons FROM public.cidades c WHERE c.id=NEW.cidade_id;
  IF v_cidade_cons IS NULL OR v_cidade_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: cidade de outro consorcio'; END IF;
  SELECT c.nome INTO NEW.cidade FROM public.cidades c WHERE c.id=NEW.cidade_id;   -- não confiar no texto do cliente
  IF NEW.empresa_id IS NOT NULL THEN
    SELECT e.consorcio_id, e.nome INTO v_empresa_cons, NEW.empresa FROM public.empresas e WHERE e.id=NEW.empresa_id;
    IF v_empresa_cons IS NULL OR v_empresa_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: empresa de outro consorcio'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.empresa_cidades ec WHERE ec.empresa_id=NEW.empresa_id AND ec.cidade_id=NEW.cidade_id) THEN
      RAISE EXCEPTION 'PROIBIDO: empresa nao atende esta cidade'; END IF;
  ELSE NEW.empresa := NULL; END IF;
  IF NEW.usuario_responsavel_id IS NOT NULL THEN
    SELECT u.consorcio_id INTO v_usuario_cons FROM public.usuarios u WHERE u.id=NEW.usuario_responsavel_id AND u.status='ativo';
    IF v_usuario_cons IS NULL OR v_usuario_cons IS DISTINCT FROM NEW.consorcio_id THEN RAISE EXCEPTION 'PROIBIDO: responsavel de outro consorcio'; END IF;
  END IF;

  IF auth.uid() IS NULL THEN RETURN NEW; END IF;      -- bootstrap/RPC definer (abrir_chamado_publico)
  IF public.is_master() THEN RETURN NEW; END IF;
  v_perfil := public.meu_perfil();

  IF TG_OP='INSERT' THEN
    IF v_perfil='consorcio' THEN
      IF NEW.consorcio_id IS DISTINCT FROM public.meu_consorcio() THEN RAISE EXCEPTION 'PROIBIDO: chamado fora do consorcio'; END IF;
      RETURN NEW;
    END IF;
    IF v_perfil='prefeitura' THEN
      IF NEW.cidade_id IS DISTINCT FROM public.minha_cidade() THEN RAISE EXCEPTION 'PROIBIDO: prefeitura so abre na propria cidade'; END IF;
      IF NEW.empresa_id IS NOT NULL OR NEW.status IS DISTINCT FROM 'Recebido' OR NEW.prioridade IS DISTINCT FROM 'Média'
         OR NEW.sla_horas IS NOT NULL OR COALESCE(NEW.sla_pausado,false) OR NEW.completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PROIBIDO: prefeitura definiu campo administrativo'; END IF;
      RETURN NEW;
    END IF;
    IF v_perfil='empresa' THEN
      IF NEW.empresa_id IS DISTINCT FROM public.minha_empresa() OR NOT public.empresa_atende(NEW.cidade_id) THEN
        RAISE EXCEPTION 'PROIBIDO: empresa fora do proprio escopo'; END IF;
      IF NEW.status IS DISTINCT FROM 'Recebido' OR NEW.prioridade IS DISTINCT FROM 'Média'
         OR NEW.sla_horas IS NOT NULL OR COALESCE(NEW.sla_pausado,false) THEN
        RAISE EXCEPTION 'PROIBIDO: empresa definiu campo administrativo no INSERT'; END IF;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'PROIBIDO: perfil nao pode inserir chamado';
  END IF;

  -- UPDATE: campos estruturais imutáveis p/ não-master
  IF NEW.protocolo IS DISTINCT FROM OLD.protocolo OR NEW.consorcio_id IS DISTINCT FROM OLD.consorcio_id
     OR NEW.origem IS DISTINCT FROM OLD.origem OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'PROIBIDO: tentativa de alterar campo estrutural'; END IF;

  IF v_perfil='consorcio' THEN
    IF NEW.consorcio_id IS DISTINCT FROM public.meu_consorcio() THEN RAISE EXCEPTION 'PROIBIDO: fora do consorcio'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='prefeitura' THEN
    IF OLD.cidade_id IS DISTINCT FROM public.minha_cidade() OR NEW.cidade_id IS DISTINCT FROM OLD.cidade_id THEN
      RAISE EXCEPTION 'PROIBIDO: prefeitura tentou mudar cidade'; END IF;
    IF (to_jsonb(NEW) - ARRAY['bairro','endereco','referencia','area','latitude','longitude','loc_src','tipo','qtd','observacoes','solicitante_nome','solicitante_tel','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['bairro','endereco','referencia','area','latitude','longitude','loc_src','tipo','qtd','observacoes','solicitante_nome','solicitante_tel','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: prefeitura alterou campo administrativo'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='empresa' THEN
    IF OLD.empresa_id IS DISTINCT FROM public.minha_empresa() OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id
       OR NEW.cidade_id IS DISTINCT FROM OLD.cidade_id THEN
      RAISE EXCEPTION 'PROIBIDO: empresa tentou mudar atribuicao/cidade'; END IF;
    IF (to_jsonb(NEW) - ARRAY['status','completed_at','observacoes','latitude','longitude','loc_src','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status','completed_at','observacoes','latitude','longitude','loc_src','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: empresa alterou campo fora da execucao'; END IF;
    RETURN NEW;
  END IF;

  IF v_perfil='garantia' THEN
    -- Garantia atua somente em chamados de garantia de seu consórcio.
    IF OLD.consorcio_id IS DISTINCT FROM public.meu_consorcio()
       OR OLD.status NOT IN ('Aguardando Garantia LED','Concluído')
       OR OLD.garantia_tipo IS NULL THEN
      RAISE EXCEPTION 'PROIBIDO: chamado nao atribuido a Garantia LED';
    END IF;
    IF OLD.status='Concluído' AND NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'PROIBIDO: garantia nao pode reabrir chamado concluido';
    END IF;
    IF OLD.status='Aguardando Garantia LED'
       AND NEW.status NOT IN ('Aguardando Garantia LED','Concluído') THEN
      RAISE EXCEPTION 'PROIBIDO: garantia so pode concluir chamado';
    END IF;
    IF OLD.status='Aguardando Garantia LED' AND NEW.status='Concluído' THEN
      IF NEW.completed_at IS NULL THEN NEW.completed_at:=now(); END IF;
      IF NEW.completed_at < OLD.created_at THEN
        RAISE EXCEPTION 'PROIBIDO: data de conclusao anterior a abertura';
      END IF;
    ELSIF NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
      RAISE EXCEPTION 'PROIBIDO: alterar data de conclusao sem concluir';
    END IF;
    -- Somente status de conclusão, data e metadados de garantia podem mudar.
    IF (to_jsonb(NEW) - ARRAY['status','completed_at','garantia_tipo',
        'garantia_obs','garantia_dt','garantia_user','updated_at']::text[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status','completed_at','garantia_tipo',
        'garantia_obs','garantia_dt','garantia_user','updated_at']::text[]) THEN
      RAISE EXCEPTION 'PROIBIDO: garantia alterou campo operacional';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'PROIBIDO: perfil sem permissao de update';
END $function$;

-- Histórico persistente gerado pelo banco em toda transição de status
-- e em edições de observações. Não depende de localStorage/cliente.
CREATE OR REPLACE FUNCTION public.v19_registrar_historico_chamado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $hist$
DECLARE v_nome text;v_acao text;v_obs text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.observacoes IS NOT DISTINCT FROM OLD.observacoes THEN RETURN NEW; END IF;

  SELECT nome INTO v_nome FROM public.usuarios
    WHERE auth_user_id=auth.uid() AND status='ativo' LIMIT 1;
  v_nome:=coalesce(v_nome,'Sistema');
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_acao:='Status alterado';
    v_obs:=coalesce(OLD.status,'Sem status')||' → '||coalesce(NEW.status,'Sem status');
  ELSE
    v_acao:='Observações alteradas';
    v_obs:='Alteração de observações do chamado';
  END IF;
  INSERT INTO public.chamado_historico(chamado_id,status,mensagem,observacao,cor,usuario_nome)
   VALUES(NEW.id,NEW.status,v_acao,v_obs,'#1251A3',v_nome);
  RETURN NEW;
END;
$hist$;

DROP TRIGGER IF EXISTS trg_v19_historico_chamados ON public.chamados;
CREATE TRIGGER trg_v19_historico_chamados
  AFTER UPDATE OF status,observacoes ON public.chamados FOR EACH ROW
  EXECUTE FUNCTION public.v19_registrar_historico_chamado();
REVOKE ALL ON FUNCTION public.v19_registrar_historico_chamado() FROM PUBLIC,anon,authenticated;
COMMIT;

-- Se a migração 04 foi aplicada, a policy de histórico preserva as permissões
-- de consulta por empresa atribuída. A UI V19 lê o histórico diretamente do banco.
