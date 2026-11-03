# Aponte Cidadão — V19 (em homologação)

**Situação:** branch `desenvolvimento-v19`. **Não liberar para produção ainda.**

## Arquivos
- `teste-v19/index.html` — nova interface isolada da V18.
- `teste-v19/v19.js` — dados completos, equipes e estoque via Supabase.
- `teste-v19/v19-fotos.js` — Storage privado e histórico real.
- `teste-v19/v19-relatorios.js` — exportações filtradas com métricas explícitas.
- `teste-v19/v19-config.js` — Portal e SLA persistentes por consórcio.
- `sql/v19/03_...sql`, `04_...sql`, `05_...sql`, `06_...sql` — migrations **não executadas**.
- `scripts/verificar-v19.mjs` — teste estático automático (node --check).

## Alterações realizadas
1. A versão `teste-v18/index.html` foi restaurada bit a bit ao conteúdo original de `main`; V18 publicada preservada.
2. Dashboard não exibe métricas ou gráficos fabricados; período/mês/cidade selecionáveis.
3. Equipes lêem/escrevem o banco com confirmação; não se baseiam em `saveDB()`.
4. Cadastro e movimentação do estoque foram preparados para RPCs atômicas com registro de movimentos; ajustes sem histórico bloqueados no frontend.
5. Empresa deixa de consultar chamados e fotos de outra empresa pela policy planejada.
6. Garantia LED pode concluir apenas chamados em garantia que pertençam ao consórcio, após migration de trigger.
7. PDF/XLSX trabalham com a mesma seleção filtrada; taxa de conclusão não é chamada de taxa de SLA.
8. Mapa não inventa coordenadas; sinaliza chamados sem GPS e filtros resultam dos dados.
9. Foto real no bucket privado e histórico lido do banco, sem usar base64 de localStorage.
10. Portal e SLA têm interface para persistir em tabelas reais, com políticas de autorização.

## Riscos e pendências ANTES DE PUBLICAR
- **Nenhuma migration foi executada em banco V19 isolado** e nenhum fluxo foi testado numa sessão real de navegador. As verificações automáticas são de sintaxe/arquivos, **não** testes funcionais ou de segurança.
- A V18 e a V19 ainda compartilham o Supabase de produção **se a interface V19 for apontada para o endpoint atual**. Criar projeto de homologação ou banco isolado, importar esquema e dados de teste, conectar configuração V19 ao ambiente próprio, executar migrations em ordem 03→04→05→06.
- Confirmar nomes de colunas e compatibilidade dos scripts em execução Postgres no projeto de homologação. Prever transação/rollback e backup antes do deploy final.
- V19-013: fluxo de **assumir chamados disponíveis** ainda não implementado, necessita RPC de projeção anônima mínima para executor autenticado e atribuição atômica, com proteção do trigger.
- V19-021: gestão de usuários e convites ainda não totalmente auditada/ajustada em V19.
- Segurança de telefone: **consulta por telefone NÃO implementada**; somente protocolo exato deve ser autorizado sem OTP.
- `notificacao_whatsapp`: preferencia armazenada, **não há envio automático**.
- SLA estimado em horas corridas: não representa dias úteis, pausas completas, feriados, reaberturas ou contratos específicos. `sla_pausado` resulta em **não apurável**; é preciso modelo canônico de contagem.
- Histórico retroativo não deve ser inventado. Confirmar políticas de insert e trigger evitando duplos registros.
- A página de mapa original ainda é Leaflet e precisa teste em navegador com dados de GPS reais e geocodificação.
- Fluxos de foto precisam ser exercitados com Auth real, usuário de outra empresa, upload duplo e leitura após F5.
- Configuração do portal deve ter dados públicos realmente aplicados pela UI de cidadão (a RPC futura de 06 bloqueia abertura/consulta; visual pode não refletir de imediato).
- Dashboard/relatórios não apresentam os mesmos KPI de SLA nas demais telas enquanto relógio canônico não estiver finalizado.
- Validar duplicação de `sla_configuracoes` por par consórcio/tipo e `estoques`, além dos registros de usuários; testes RLS por consórcio requerem 2 tenants.
- **NÃO fazer merge do PR** e não publicar `teste-v19/` como produção antes de os critérios de aceite críticos passarem.

## Ordem do release
1. Validar todos os scripts numa instância de **homologação isolada**.
2. Executar suíte de regressão perfis Master, Consórcio, Prefeitura, Empresa A, Empresa B e Garantia e ataques diretos às APIs.
3. Verificar 21 critérios V19 do dossiê, além dos 38 testes de aceite.
4. Corrigir os testes reprovados, rodar verificação estática e testes manuais, aprovar o merge.
5. Preparar migração de produção com backup, observabilidade e rollback.

## Estado da limpeza de teste V18
O usuário executou manualmente exclusão de um material de teste e seu estoque; pós-consulta confirmou ambos EXCLUÍDO. Isso é a única alteração de dados de produção realizada durante esta etapa.
