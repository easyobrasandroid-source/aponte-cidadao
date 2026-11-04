# Aponte Cidadão V19 — Estado verificado da homologação

**Atualização:** 2026-11-04. **Branch:** `desenvolvimento-v19`.

## Ambiente

- **Projeto V19 separado:** `aponte-cidadao-v19-homologacao`, em São Paulo, com banco novo e 14 tabelas. A produção V18 não deve ser alterada.
- **Não executar o esquema legado `supabase_schema.sql` nem o pacote antigo `08_INSTALACAO_CONSOLIDADA_SOMENTE_HOMOLOGACAO.sql` neste banco.** Ambos foram escritos para o esquema anterior e não representam o pipeline de instalação limpa.
- **Arquivos para a base nova:** `sql/v19/01_BASE_LIMPA_HOMOLOGACAO.sql`, `02_DIAGNOSTICO_POS_BASE_SOMENTE_LEITURA.sql`, `03_RLS_LEITURA_PRIVADA_HOMOLOGACAO.sql`; depois os scripts de testes de Auth e massa de dados.
- Esta anotação registra resultados enviados pelo usuário (CSV/screenshots). Não equivale a auditoria independente do banco.

## Testes realizados e aprovados por evidência enviada

- 14/14 tabelas criadas com RLS ativo e, no diagnóstico inicial, uma policy por tabela.
- 2 consórcios, 3 municípios e 3 empresas fictícias; 7 contas Supabase Auth vinculadas.
- Leitura por API real: Master 3 chamados, empresas Alfa A/B e Beta A com seus chamados, Consórcio Alfa 2, Prefeitura Alfa 1 2, Garantia Alfa 0 antes do primeiro encaminhamento.
- Garantia LED: leitura de chamado elegível confirmada, chamada não responsável bloqueada com HTTP 403.
- SQL 17 instalou `v19_concluir_garantia(uuid)` e trigger de histórico; SQL 18 passou a permitir conclusão por perfil Garantia do consórcio ou empresa já atribuída na cidade autorizada.
- Teste 20: empresa Alfa B não concluiu chamado Alfa A; status/histórico intactos.
- Teste 21: empresa Alfa A concluiu o chamado Alfa-1, com data, responsável e histórico (1 evento).
- Teste 23: técnico Garantia Alfa concluiu Alfa-2, mantendo empresa e cidade, com histórico (1 evento).
- Teste 24: segunda conclusão de Alfa-2 recusada (HTTP 400), status/datas/histórico preservados.

## Próxima etapa

- **SQL 25:** `sql/v19/25_ATRIBUICAO_SEGURA_EMPRESAS_HOMOLOGACAO.sql` — criado na branch, **ainda não confirmado como executado**. Instala `v19_listar_disponiveis(integer)` e `v19_assumir_chamado(uuid)`, com escopo de empresa e cidade, atualização atômica e histórico.
- Criar um chamado fictício SEM empresa e testar listagem apenas nas cidades autorizadas, atribuição concorrente entre Alfa A e Alfa B e bloqueio de outra empresa/consórcio.
- Depois implementar/validar abertura, edição, conclusão normal, reabertura e histórico. Revisar modelos de dados e contratos antes de permitir UPDATE direto.
- Validar autenticação real e isolamento em outras tabelas, fotos privadas, estoque, equipes, portal, SLA, mapas, relatórios e experiências de usuário.
- Executar regressão formal dos 21 critérios V19 + 38 casos de aceite e piloto antes de merge/publicação.

## Riscos ainda abertos

- RLS já foi testado em cenários de chamados, mas não em todos os objetos/RPCs.
- Controle de acesso a fotos, telefone, publicações e campos pessoais ainda requer testes de API.
- Dashboard e relatórios ainda não possuem modelo canônico de SLA (feriados, pausas, dias úteis, reaberturas).
- Frontend `teste-v19/` tem integrações escritas para a estrutura antiga; **não apontar para V19 como produção sem adaptação e validação**.
- A aplicação da V19 e a migração do legado permanecem não autorizadas até concluir os portões críticos.

## Verificação operacional adicional — 2026-11-04

- SQL 25: `v19_listar_disponiveis` e `v19_assumir_chamado` instaladas; 5/5 diagnósticos OK (resultado enviado pelo usuário).
- SQL 26: chamado de disputa `V19-TESTE-ATRIBUICAO-ALFA-1` criado sem empresa atribuída, sem histórico inicial.
- Teste 27: Alfa B venceu a disputa (RPC 200), Alfa A foi bloqueada (RPC 403), 1 histórico de atribuição, sem visibilidade para a perdedora (print do usuário).
- SQL 28: `v19_atualizar_status_chamado(uuid,text)` instalada; 5/5 diagnósticos OK.
- Teste 29: Alfa B moveu chamado de Recebido para Em programação; histórico 1 → 2 (print do usuário).
- Teste 30: Alfa B moveu chamado de Em programação para Em execução; histórico 2 → 3; sem data de conclusão (prints do usuário).
- Próximo: Teste 31 conclusão de chamado comum pela Alfa B; Teste 32 repetição da conclusão deve ser negada e preservar histórico. Painel HTML único preparado para uso local.
- A homologação geral continua incompleta. Não fazer merge nem apontar V19 para produção.

## SQL 33–35 — Estoque (evidências enviadas em 2026-11-04)

- SQL 33: as tabelas `materiais`, `estoques`, `movimentacoes` e `chamado_materiais` existem, com RLS ativo e sem DML direto para authenticated.
- SQL 34: as quatro RPCs de estoque/consumo consultadas não estavam instaladas; as quatro tabelas estavam vazias, sem anomalias estruturais detectáveis nesses dados.
- SQL 35: o usuário confirmou 5/5 diagnósticos **OK** para instalação da RPC de cadastro, movimentação manual, bloqueio anon e DML direto.
- Próximo: painel de Testes 36–40 preparado localmente — cadastro fictício pela conta Consórcio Alfa, tentativa indevida de Empresa Alfa A, entrada +5, saída -3 e retirada maior que saldo. **Ainda não executado pelo usuário.** Consumo por chamado e isolamento entre consórcios permanecem pendentes.
