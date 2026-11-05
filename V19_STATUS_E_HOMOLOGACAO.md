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

## Homologação administrativa de estoque — Testes 36 a 40 (2026-11-04)

Evidências: seis screenshots do usuário com resultados finais.

- **Teste 36 aprovado:** material fictício `V19-TESTE-ESTOQUE-ALFA-36` cadastrado no Consórcio Alfa, 20 unidades contratadas, 12 disponíveis, com movimento inicial `entrada 12`.
- **Teste 37 aprovado:** Empresa Alfa A enxerga saldo, mas a RPC de ajuste manual retornou HTTP 403; saldo e histórico inalterados.
- **Teste 38 aprovado:** entrada +5: disponível 12 → 17; contratado 20 → 25; movimentos 1 → 2.
- **Teste 39 aprovado:** saída -3: disponível 17 → 14; contratado mantém 25; movimentos 2 → 3.
- **Teste 40 aprovado:** tentativa de retirar 100 retornou HTTP 400 `SALDO_INSUFICIENTE`, sem alterar saldo/contratado/histórico.

**Não confundir este escopo com homologação integral de estoque.** Ainda faltam consumir material por chamado, edição/estorno, concorrência real de saldos e isolamento entre consórcios.

- **SQL 41 preparado, NÃO confirmado como executado:** `sql/v19/41_CONSUMO_ATOMICO_MATERIAL_CHAMADO_HOMOLOGACAO.sql`. Implementa a RPC `consumir_material_chamado(uuid,uuid,numeric)` sem sobrescrever SQL35, com verificação de Auth, empresa atribuída/cidade/consórcio, status ativo, saldo suficiente e lançamento em três tabelas na mesma transação.

## Consumo por chamado — SQLs 41 e 42 (2026-11-04)

- SQL 41 instalado (5/5 diagnósticos `OK`, resultado informado pelo usuário): `public.consumir_material_chamado(uuid,uuid,numeric)` disponibilizada apenas a `authenticated`; DML direto segue negado.
- SQL 42 executado (resultado informado): chamado `V19-TESTE-CONSUMO-ALFA-B-1`, no Município Alfa 1, atribuído à Empresa Alfa B, status `Em execução`; material `V19-TESTE-ESTOQUE-ALFA-36` com disponível **14**, contratado **25**, nenhum consumo ou movimento vinculado ao chamado.
- Painel HTML para **Testes 43–47** gerado como artefato desta conversa, com Auth real das contas Consórcio Alfa, Empresa Alfa A/B e Beta A, sem armazenamento de credenciais. Etapas: pré-verificação, bloqueio da empresa não atribuída, consumo autorizado de 2 unidades (saldo final esperado 12), rejeição por saldo insuficiente (100 unidades), isolamento entre consórcios. **Testes ainda não executados pelo usuário**.
- O SQL 41 não implementa edição/estorno de consumo: estes fluxos ainda exigem migração específica e homologação.

## Homologação de consumo — Testes 43–47 aprovados (2026-11-04)

Evidência: cinco capturas de tela fornecidas pelo usuário.

- **Teste 43**: pré-verificação de Gestor Alfa, Empresa Alfa B (atribuída) e Alfa A (não atribuída); material com saldo 14/25, 3 movimentações e nenhum consumo inicial.
- **Teste 44**: Alfa A bloqueada (HTTP 403); saldo 14/14 e nenhum novo consumo/movimento/histórico.
- **Teste 45**: Alfa B consumiu 2 unidades a R$50 cada. Saldo **14→12**; contratado 25; movimentações **3→4**; itens de consumo **0→1**; histórico do chamado **0→1**; custo R$100.
- **Teste 46**: tentativa de consumir 100 unidades retornou HTTP 400 `SALDO_INSUFICIENTE`; quantidades, itens, movimentos e histórico preservados.
- **Teste 47**: Empresa Beta A de outro consórcio não enxerga chamados ou materiais Alfa e recebeu HTTP 403 tentando consumir; dados preservados.

### Próximo passo: SQL 48 / edição e estorno

- Arquivo: `sql/v19/48_EDICAO_ESTORNO_CONSUMO_HOMOLOGACAO.sql` criado na branch; **execução ainda pendente de confirmação do usuário**.
- Instala `editar_material_chamado(uuid,numeric)` e `remover_material_chamado(uuid)`, com autorização real, travas de transação, histórico e alteração de saldo atômica.
- Cenário planejado após os cinco diagnósticos OK: Alfa A deve ser bloqueada; Alfa B edita 2→3 (saldo 12→11), reduz 3→1 (saldo 11→13), e estorna 1 unidade (saldo 13→14), mantendo trilha de movimentos/histórico. A edição de item removido deve ser bloqueada. Não executar esses cenários antes de instalar e verificar o SQL 48.

## SQL 48 instalado — Edição/estorno de consumo (2026-11-04)

- Usuário confirmou 5/5 `OK`: RPCs `editar_material_chamado(uuid,numeric)` e `remover_material_chamado(uuid)` instaladas; executáveis por `authenticated`, negadas a `anon`, escrita direta negada.
- Foi preparado o painel HTML **Aponte_V19_Painel_Edicao_Estorno_Testes_49_a_55.html** (artefato local da conversa). Realiza pré-verificação, bloqueio de Empresa Alfa A, edição Alfa B 2→3 (saldo 12→11), edição 3→1 (saldo 11→13), bloqueio de estorno por Alfa A, estorno autorizado (saldo 13→14), bloqueio de estorno duplicado. Os testes são sequenciais, com verificações de movimentações, auditoria e totais.
- **Testes 49–55 ainda pendentes de execução pelo usuário.** Não reaplicar SQL 48 nem recriar fixtures. Caso falhe, não repetir a operação antes de auditar banco.

## Testes 49–55 — Edição e estorno de consumo aprovados (2026-11-04)

Evidência: sete screenshots fornecidos pelo usuário. Resultado de aplicação observado (sem auditoria independente do banco).

- 49: Pré-verificação das identidades, chamado ativo, item de consumo 2 unidades/R$100, saldo 12, contratado 25, quatro movimentos e um evento de histórico — OK.
- 50: Alfa A não responsável tentou editar; HTTP 403, saldos/itens/movimentos/histórico inalterados — OK.
- 51: Alfa B editou consumo de 2 para 3; saldo **12→11**, total do item R$100→R$150; movimentos **4→5**, histórico **1→2** — OK.
- 52: Alfa B editou de 3 para 1; saldo **11→13**, total R$150→R$50; movimentos **5→6** (devolução 2), histórico **2→3** — OK.
- 53: Alfa A bloqueada no estorno, HTTP 403, sem mudanças — OK.
- 54: Alfa B realizou estorno integral do item remanescente; saldo **13→14**, contratado 25, itens ativos **1→0**, movimentos **6→7**, histórico **3→4** — OK.
- 55: estorno duplicado negado HTTP 403 (`ITEM_NAO_DISPONIVEL`); saldos, movimentos e histórico preservados — OK.

Próximo: **SQL 56** `sql/v19/56_AUDITORIA_FINAL_ESTOQUE_SOMENTE_LEITURA.sql` preparado, **não executado pelo usuário**, reconciliará saldos x ledger do material fictício, linhas ativas e integridade entre consórcios. Após isso, priorizar concorrência e integração com UI V19 em vez de multiplicar páginas HTML avulsas. Não fazer deploy de produção ainda.

## SQL 56 e início da integração frontend (2026-11-04)

- **SQL 56 concluído com 11/11 OK** (CSV fornecido pelo usuário): 1 material, 1 estoque, saldo 14 e contratado 25, 7 movimentos; saldo reconstituído 14 igual ao banco; 1 chamado ativo Em execução, 0 itens de consumo, 4 eventos de histórico; nenhuma divergência de consórcio ou saldo inválido.
- **Bloqueador crítico descoberto** durante inspeção: `teste-v19/index.html` ainda apontava para a URL/chave pública da V18. Isso foi corrigido **somente na branch `desenvolvimento-v19`**, sem tocar `main`.
- Configuração agora fixa o Supabase de homologação `https://xurrhczvyqpwyjemight.supabase.co`, requer chave pública `sb_publishable_` fornecida pelo operador na abertura (guardada apenas em sessionStorage para aba), e sessões Auth em armazenamento de chave `aponte_v19_homolog_session`, sem compartilhar tokens da V18.
- Cabeçalho `Authorization` agora só é enviado quando houver JWT da sessão de usuário; a chave `sb_publishable_` vai no cabeçalho `apikey` (compatível com o formato opaco atual).
- Aplicação da V19 bloqueia por padrão `POST/PATCH/DELETE` em tabelas via `sbFetch`, permitindo apenas POST às RPCs previamente instaladas e homologadas. Chamadas antigas de escrita falharão de forma explícita; **não significa que a interface está integrada por completo**.
- Removido mecanismo residual de popular estoque com seed: se o catálogo estiver vazio, permanece vazio.
- Bloco `<script>` principal de `teste-v19/index.html` foi compilado com `new Function` em ambiente de ferramenta e passou **somente verificação de sintaxe**; nenhum teste em navegador real, CI ou Supabase foi executado para essa alteração.
- Próximo portão: abrir a V19 pela branch isolada, usar chave `sb_publishable_` do projeto correto e fazer **smoke test apenas de leitura** (login de consórcio, dados do estoque, consulta de chamados, F5/logout/login). Não executar alterações pela interface antes de implementar as RPCs faltantes e testar os fluxos integrais. Depois focar gravações de equipes, abertura/edição de chamados, portal, SLA, fotos, relatórios e dashboards.

**A V19 NÃO está pronta para produção. A V18 deve permanecer intacta até regressão geral e piloto.**

## Smoke test da interface V19 + histórico real do estoque (2026-11-04)

- Evidência visual do usuário: login Consórcio Alfa carregou dashboard do Supabase, mostrando 6 chamados (3 concluídos, 1 em programação/execução) e aviso de SLA ainda não homologado.
- Evidência visual do usuário: tela **Estoque** exibiu exatamente um material fictício `V19-TESTE-ESTOQUE-ALFA-36`, contratado 25, disponível 14 (56%), preço R$50, estoque crítico 0, três movimentos do tipo saída/consumo no mês. **Leitura de estoque aprovada nos dados vistos.**
- Revisão de código confirmou que `teste-v19/v19.js` já sobrescreve `sbSaveMaterial` para RPC `v19_salvar_material` e `salvarMovimentacao` para RPC `v19_movimentar_estoque`; ainda não testadas na interface principal, apesar de homologadas em painéis separados.
- **Bug de histórico corrigido** na branch `desenvolvimento-v19`: o botão Histórico passou a consultar o ledger `movimentacoes` (incluindo devoluções e estornos), não `chamado_materiais` (onde itens estornados são apagados). Também envia observação digitada pelo operador à RPC de movimentação.
- Compilação estática de `v19.js` com JavaScript `new Function` passou. **Ainda não foi testado no navegador pelo usuário** após a correção; rebaixar o ZIP atualizado e validar apenas leitura pelo botão Histórico, esperando sete movimentações do material.
- Não realizar ajustes pelo frontend até a próxima pré-verificação e teste controlado de RPC em registro fictício novo. V18 preservada.

## Smoke test das abas Histórico e Materiais do chamado (2026-11-04)

Capturas do usuário para o protocolo `V19-TESTE-CONSUMO-ALFA-B-1` confirmaram:

- Aba Histórico: **4 eventos reais** exibidos (consumo, edição para 3, devolução para 1 e estorno integral), todos associados à Empresa Alfa B, no status `Em execução`. Nota de UX: títulos repetem o status `Em execução` em vez de descrever o tipo de evento; observações permitem entender a ação.
- Aba Materiais: **nenhum item ativo** após o estorno, coerente com os Testes 54/55 e SQL 56.
- **Leitura do drawer aprovada nesse cenário.** Ainda não equivale a homologação de alterações por essa interface.
- Auditoria de código: `alterarStatus`, `confirmarConclusao`, `confirmarGarantia`, `salvarDrawer` e operações em lote têm trechos do fluxo legado que recorrem a `sbSaveChamado`/gravação direta. O bloqueio V19 de `sbFetch` evita persistência indevida, mas os botões não estão homologados. **Não executar** ações de status/conclusão/garantia/salvar, nem lote, até substituição por RPCs V19 adequadas. RPC de status comum existente: `v19_atualizar_status_chamado(p_chamado_id,p_novo_status)`. RPC de conclusão de garantia existente: `v19_concluir_garantia(p_chamado_id)`.
- Próxima validação imediata sem escrita: testar busca e filtro do chamado com resultado conhecido e limpar filtro. Depois integrar botões de status com origem de verdade no Supabase e histórico via trigger, usando novo chamado sintético para testes de escrita.

## Teste UI: filtro de chamados e primeira integração de status (2026-11-04)

- Capturas do usuário: no filtro **Em execução**, a tabela apresentou somente `V19-B-1`, Empresa Alfa B, 1 resultado. Após **Limpar**, retornaram os 6 registros esperados. Leitura e filtros aprovados visualmente.
- `teste-v19/index.html` atualizado no commit **2540b66bf450234d13d12e51586134435c5a95cc**: os passos de status comum **Em programação**, **Em execução** e **Aguard. material** usam agora `POST rpc/v19_atualizar_status_chamado`, com UUID real do chamado, sessão Auth, confirmação humana, checagem de `ok=true` e status de retorno, seguida por nova leitura do banco. Histórico dessas transições é gerado **pelo trigger do banco**, sem escrita manual no frontend.
- **Bloqueados temporariamente** na interface atualizada os fluxos legados de edição genérica de chamado, alterações em lote, encaminhar Garantia LED, Concluir e Novo chamado: exigem RPCs dedicadas e não devem simular persistência em localStorage. As funções de backend de garantia e conclusão foram homologadas isoladamente, mas seus respectivos botões ainda aguardam integração segura.
- Verificação estática de sintaxe do script inline passou; **nenhum teste da nova interface em navegador ou Supabase foi executado** após o commit. O operador precisa baixar novo ZIP antes de testar.
- Próximo teste isolado e seguro: consórcio Alfa abrir o chamado fictício **`V19-A-A`**, que permanece `Recebido` conforme captura de 2026-11-04, escolher `Em programação`, confirmar uma única vez e validar status persistente após F5 e 1 histórico automático. Fazer pré-leitura antes de mudar, pois dados de teste podem ter mudado. Não usar o protocolo `V19-B-1` para esse primeiro teste.
- NÃO APLICAR EM PRODUÇÃO; V18 intocada.

## Status via interface: primeiro teste com persistência e histórico (2026-11-04)

- Usuário aplicou **Recebido → Em programação** ao chamado fictício `V19-TESTE-RLS-ALFA-A` (listagem `V19-A-A`) usando a interface `teste-v19/index.html`, autenticado como Gestor Consórcio Alfa.
- A interface exibiu status atualizado; usuário pressionou F5 e apresentou print mostrando o status persistente e a aba Histórico com **1 evento** `Recebido → Em programação`, responsável **Gestor Consórcio Alfa**, horário **04/11/2026 12:45:04** (horário apresentado no navegador).
- **Teste funcional de status via RPC aprovado no cenário específico**. Próximo teste seguro com a mesma fixture: **Em programação → Em execução**; não concluir e não acionar garantia.
- Ajuste de UX: `index.html` agora esconde a faixa `Execução finalizada? Marque como concluído` enquanto os botões legados de conclusão e garantia estão bloqueados (commit `ef0515b8618ccd0ab0deece7a1570efaa279a62c`). Alteração ainda não testada no navegador; vale apenas para quem baixar versão nova. A versão local anterior continua habilitada para teste da RPC de status comum.

## Segunda transição de status na UI — aprovado (2026-11-04)

- Print do usuário após F5 no chamado `V19-TESTE-RLS-ALFA-A` confirmou **Em programação → Em execução** e **2 eventos** no histórico, atribuídos ao Gestor Consórcio Alfa; segundo evento mostrado em 04/11/2026 12:48:01.
- Lista de 6 chamados preservada. A UI fez atualização persistente via RPC `v19_atualizar_status_chamado` no fluxo comum.
- Próximo cenário de escrita controlado, permitido no SQL 28: **Em execução → Aguard. material**, com histórico esperado de 3 eventos. NÃO clicar em Concluir ou Garantia; continuam bloqueados na UI atual. Após conferir, pode-se planejar volta **Aguard. material → Em execução** sem recriar fixture.
- Pendente de UX: restringir círculos clicáveis de acordo com matriz de transições SQL 28; actualmente fluxos inválidos são bloqueados pelo servidor, mas a UI pode oferecê-los.

## Terceira transição e integração de conclusão RPC (2026-11-04)

- Prints do usuário: chamado `V19-TESTE-RLS-ALFA-A` passou de **Em execução** para **Aguard. material**; após F5 continuou no novo estado; timeline exibiu **3 eventos**, terceiro `Em execução → Aguard. material`, responsável Gestor Consórcio Alfa, em 04/11/2026 12:50:29.
- Usuário observou corretamente que a etapa **Concluído** estava bloqueada; era intencional porque o fluxo antigo do frontend tentava gravação direta em tabelas.
- Atualizado `teste-v19/index.html` no commit `cde4dae71ce81bcc12eb6e80d074f44624482a54`: habilita botão **Concluir** e círculo final somente para papéis/estados elegíveis. Chamado comum usa RPC `v19_atualizar_status_chamado(chamado_id,'Concluído')` (SQL 28; consórcio, master ou empresa responsável autorizada); Garantia LED usa `v19_concluir_garantia(chamado_id)` (SQL 18; técnico garantia no mesmo consórcio ou empresa atribuída/autorizada). A autorização final fica exclusivamente no banco.
- Fluxo de conclusão tem modal e confirmação explícita, impede cliques concorrentes, exige retorno da RPC com `ok=true`, `status=Concluído` e `completed_at`, relê os dados e **não escreve histórico manual nem atualiza o chamado por PATCH**. Modal informa que a data é do servidor e não oferece observações que a RPC não receberia.
- UX: círculos clicáveis de status comum passam a respeitar matriz do SQL 28, evitando transições inválidas no frontend (o servidor continua a autoridade).
- Testes estáticos: sintaxe do JavaScript inline válida; guardas puras de interface verificadas em **11/11 cenários**, incluindo papel da garantia, empresa errada, bloqueio de conclusão duplicada e retorno permitido `Aguard. material → Em execução`.
- **Ainda sem homologação do botão Concluir no navegador ou Supabase** desde o commit. A versão ZIP local anterior continua bloqueando a etapa final; operador deve baixar o ZIP mais recente. Próxima etapa recomendada: retornar o chamado fictício `V19-A-A` para **Em execução** e confirmar histórico após F5; depois abrir a versão nova para pré-verificar conclusão e executar apenas uma vez, com confirmação do usuário. Não executar em produção.

## Homologação pela interface — conclusões pelo consórcio e pela empresa (05/11/2026)

Evidência: capturas de tela apresentadas pelo operador, no banco de homologação V19.

- Chamado `V19-TESTE-RLS-ALFA-A` (listagem `V19-A-A`): o Gestor Consórcio Alfa concluiu em 05/11/2026 07:02:11. Estado `Concluído` persistiu após F5. Timeline exibiu **5 eventos**, último `Em execução → Concluído` e responsável `Gestor Consórcio Alfa`.
- Login **Empresa Alfa B**: listagem exibiu apenas **4 chamados** da própria empresa, sem os 2 chamados da Alfa A; isolamento visual de leitura aprovado no cenário.
- Chamado `V19-TESTE-RLS-ALFA-B` (listagem `V19-A-B`): Empresa Alfa B alterou `Recebido → Em programação → Em execução → Concluído`. F5 confirmou persistência da primeira mudança e histórico; última conclusão registrada em **05/11/2026 07:45:17**, como `Concluído`, com **3 eventos** e último `Em execução → Concluído`, responsável `Empresa Alfa B`. O botão Concluir aparece oculto na tela final.
- **Aprovado nos cenários específicos:** autorização da própria empresa e do gestor, conclusão por RPC, histórico, identificação do responsável, status final e data. A captura final não comprova isoladamente novo F5 após a conclusão da Alfa B; solicitar se necessário.
- **Ainda pendente:** ensaio negativo de conclusão duplicada no fluxo atual (já havia testes isolados de servidor), isolamento reverso Alfa A versus B, teste de Garantia LED na interface atual e investigação de SLA `Não apurável (estimativa)`. Não inferir cobertura universal de papéis/transições.
- Não criar nem alterar dados de produção. V18 permanece fora do escopo.

## Garantia LED pela interface — pré-verificação e SQL 57 (05/11/2026)

- Login **Técnico Garantia Alfa** acessou **Chamados em Garantia LED** e viu **2 chamados fictícios**: `V19-A-1` (Empresa Alfa A) e `V19-A-2` (Empresa Alfa B), ambos **Concluído**. Isso confirma leitura do histórico visível, **não demonstra nova conclusão via UI**.
- Criado `sql/v19/57_MASSA_GARANTIA_LED_INTERFACE_HOMOLOGACAO.sql` na branch `desenvolvimento-v19`, commit `75b941084e0dd0a291c4de41268d35a668c18fec`. O arquivo **NÃO FOI EXECUTADO** no Supabase.
- SQL 57 prepara **dois novos chamados fictícios pendentes** (um Alfa A e um Alfa B), guardados por consórcio, RPCs, contas vinculadas e cidade habilitada. A transação falha se a fixture já existir, para impedir repetição; não toca dados antigos, produção ou políticas.
- Próximo passo: operador executa **uma única vez** SQL 57 no **projeto Supabase V19 de homologação**, compartilha apenas a tabela final (esperado 2 linhas `Aguardando Garantia LED`, `conclusao_pendente=true` e 0 históricos) — jamais compartilhe chaves/senhas.
- Só então atualizar F5 no login Garantia Alfa e testar a primeira conclusão na interface. Depois testar segunda com empresa atribuída, validando histórico/persistência e isolamento. V18 não tocada.

## Garantia LED — conclusão pela interface do Técnico Garantia Alfa validada (05/11/2026)

- Chamado SQL 57 `V19-TESTE-UI-GARANTIA-ALFA-A-57`, Empresa Alfa A, foi concluído pelo perfil **Técnico Garantia Alfa** usando a interface local V19; print do Resumo mostra `Concluído`, conclusão em **05/11/2026 08:03:47**, empresa preservada, e ação de conclusão indisponível.
- Print da aba Histórico mostra **1 evento**, transição `Aguardando Garantia LED → Concluído`, autor **Técnico Garantia Alfa**, mesma data/hora.
- Segundo chamado `V19-TESTE-UI-GARANTIA-ALFA-B-57`, Empresa Alfa B, permaneceu em `Aguardando Garantia LED` e será usado para validar conclusão pela **empresa responsável**, sem repetir o primeiro teste.
- Os prints comprovam estado e histórico, mas não explicitam novo F5 após a conclusão; registrar persistência após recarregar no próximo cenário.
- Corrigida abreviação de protocolos longos na listagem (commit `a729e320633959429a326cc0ecec0998a51d9781`): agora diferencia `V19-…-GARANTIA-ALFA-A-57` e `V19-…-GARANTIA-ALFA-B-57`, título HTML com número completo. **Correção disponível somente no próximo ZIP**, ainda não validada no navegador.

## Garantia LED — conclusão pela empresa responsável na interface (05/11/2026)

- Evidência: dois prints do login **Empresa Alfa B** na interface V19 de homologação; protocolo completo `V19-TESTE-UI-GARANTIA-ALFA-B-57`.
- Aba Resumo: status final **Concluído**, conclusão em **05/11/2026 08:07:03**, empresa atribuída `TESTE V19 - Empresa Alfa B`, cidade `Municipio Alfa 1`, botão Concluir indisponível.
- Aba Histórico: **1 evento**, transição `Aguardando Garantia LED → Concluído`, responsável `Empresa Alfa B`, timestamp **05/11/2026 08:07:03**.
- Assim foram aprovados os dois cenários positivos de conclusão de Garantia LED pela interface: **Técnico Garantia Alfa** sobre chamado Alfa A e **empresa responsável Alfa B** sobre chamado Alfa B, com identificação e histórico correto.
- Não há evidência inequívoca de F5 após esse último teste; validar persistência em recarregamento explicitamente.
- Pendências antes da homologação ampla: tentativas negativas de operação por empresa não responsável/consórcio cruzado, prevenção de segunda conclusão pela interface/API atual, SLA marcado `Não apurável (estimativa)`, e validação visual da abreviação de protocolo corrigida no GitHub mas ainda não implantada na cópia local.

## Garantia LED — persistência após F5 confirmada (05/11/2026)

- Operador pressionou F5 e enviou capturas da aba Histórico e Resumo da **Empresa Alfa B**, chamado `V19-TESTE-UI-GARANTIA-ALFA-B-57`.
- Após atualização: status **Concluído**, mesma data/hora de conclusão **05/11/2026 08:07:03**, mesmo responsável **Empresa Alfa B**, e **um único evento** de histórico `Aguardando Garantia LED → Concluído`.
- A ação de conclusão permanece indisponível no drawer. **Persistência após F5 aprovada** nesse cenário; isso não substitui teste de repetição direta da RPC como usuário autenticado.
- Cenários positivos de conclusão aprovados na interface até aqui: gestor conclui chamado comum; empresa responsável conclui chamado comum; técnico de garantia conclui LED; empresa responsável conclui LED.
- Ainda pendente para declaração de pronto para produção: inspeção consolidada de permissões negativas (incluindo impossibilidade de concluir garantia de outra empresa), anti-duplicação pela RPC, cálculo de SLA (atualmente 'Não apurável (estimativa)'), correção de protocolo abreviado na cópia local e demais módulos não cobertos.

## Continuidade — auditoria consolidada de permissões + diagnóstico SLA (05/11/2026)

- **Revisão estática** dos arquivos instalados em `sql/v19/18_PERMITIR_CONCLUSAO_EMPRESA_RESPONSAVEL_E_GARANTIA_HOMOLOGACAO.sql` e `28_STATUS_CHAMADOS_COMUNS_HOMOLOGACAO.sql`: ambas RPCs exigem JWT `authenticated`, usuário ativo, validação de consórcio/perfil; empresa atribuída e autorizada na cidade; lock `FOR UPDATE`; bloqueio de chamado já concluído; histórico automático via trigger. **A revisão estática não substitui um teste real no banco**.
- **SQL 58** criado no GitHub: `sql/v19/58_AUDITORIA_CONCLUSOES_SEGURANCA_SLA_SOMENTE_LEITURA.sql`. É uma única consulta SELECT, sem alterações, para verificar estado das duas fixtures 57, um evento por chamado, RLS, concessões de EXECUTE/UPDATE/INSERT e contagens de prazos e regras SLA. **Ainda não executado no Supabase**.
- **SLA:** `teste-v19/v19-relatorios.js` calcula somente uma estimativa em horas corridas para registros com `sla_horas` válido; pausa sem histórico de duração e ausência de prazo tornam o resultado não apurável. Não declarar SLA contratual cumprido sem regra aprovada.
- **Corrigida inconsistência visual/operacional em `teste-v19/v19-config.js`**: antes mostrava ao administrador botão para editar/salvar SLA usando PATCH/POST direto, mas `sbFetch` V19 bloqueia escrita em tabelas sem RPC. Agora SLA é explicitamente **somente leitura**, não oferece botão de salvar e os handlers de gravação informam que nenhuma alteração ocorreu (commit `a099eaca47884a69602767e5b94804532c2c4b68`). **Mudança disponível apenas após baixar nova versão da branch**, não aplicada no ZIP local.
- **Situações pendentes**: executar SQL 58 no Supabase V19 (somente leitura) e devolver resultado `verificacao,resultado,detalhe`; para isolar ACL de verdade, manter testes com JWT das empresas (SQL Editor admin não simula papéis); definir modelo contratual de SLA antes da ativação, bem como RPC segura de configuração. Corrigir o módulo Config. portal, que ainda oferece gravação direta bloqueada pela V19, antes de homologá-lo.
- V18 e banco de produção não foram acessados nem modificados.

## Resultado enviado pelo operador — SQL 58 (05/11/2026)

- **10/13 verificações OK**: consórcio teste Alfa encontrado; RLS de `chamados` e `chamado_historico` ativo; INSERT/UPDATE direto bloqueado para `authenticated` e `anon`; funções `v19_concluir_garantia(uuid)` e `v19_atualizar_status_chamado(uuid,text)` presentes, executáveis apenas por `authenticated`; duas fixtures de Garantia LED 57 concluídas com `completed_at` e **um evento por chamado**.
- **Duas informativas**: 8 chamados Alfa, **0 com `sla_horas` válido e 8 sem prazo**; **0 regras de `sla_configuracoes`**. **Uma pendência**: calendário de SLA contratual, pausas e horário útil. Logo, `SLA não apurável` é o resultado fiel, e não deve ser promovido a "no prazo"/"fora do prazo".
- **Correção de frontend em branch**, commit `fa8a1e6202dd86e190fe22d6eaf421a8271b9830`: removido fallback implícito `48` nas normalizações de `sla_horas` e `sla` em `teste-v19/index.html`. Continua **sem regras contratuais** e **sem modificação de banco**; a cópia local do operador não é atualizada automaticamente.
- **Ainda não comprovados pelo SQL 58:** bloqueio por JWT de empresa cruzada, uso de RPC por outro consórcio, tentativas duplicadas no fluxo com sessões reais, nem conformidade do SLA; SQL Editor não substitui esses ensaios. Confirmação do SLA contratual e escopo por consórcio/município, tipo e área é pré-requisito de qualquer SQL que escreva regras.

## Decisão funcional do SLA — dias corridos (05/11/2026)

O responsável pelo produto definiu **dias corridos, não dias úteis**, para os prazos do Aponte Cidadão V19. Regras:
- Unidade de configuração/apresentação: **dia corrido**; 1 dia = **24 horas** contadas desde data/hora de abertura, incluindo sábados, domingos e feriados (ex.: sexta-feira 10h + 3 dias = segunda-feira 10h).
- Preservar internamente `sla_horas`, `sla_configuracoes.urb_prazo/urb_alerta/rur_prazo/rur_alerta` em horas para compatibilidade; converter exibição para dias dividindo por 24 e futuros valores de entrada por multiplicação por 24, **sem arredondar antes da comparação de datas**.
- Não inventar número de dias por categoria, município, consórcio, área urbana/rural; depende de parâmetro contratual a ser informado. SQL 58 retornou **8 chamados sem prazo válido e 0 regras**. Mostrar "SLA não apurável" até a configuração segura via RPC e validação dos prazos.
- **Pausas** na garantia LED e demais exceções exigem política explícita e trilha de períodos; os cálculos atuais tratam pausados sem duração como não apuráveis. Não considerar garantia automaticamente dentro/fora do prazo.
- Ajustado `teste-v19/v19-config.js` para tabela somente leitura com cabeçalhos em **dias corridos** e conversão dos valores de horas existentes (commit `3f3d2a76968ed1b004b36307b31b6447ad4129a0`).
- Ajustado `teste-v19/v19-relatorios.js` para exportações/avisos em dias corridos, preservando precisão da comparação em horas internamente (commit `1db1fc864271686ef19c45d1ceeb33da95579148`).
- Ajustado `teste-v19/index.html` para indicador de tempo restante em dias corridos, prazo exportado em dias e remoção de valor médio fictício em exportador legado (commits `78775501b7a01dde2ff762f95f35518474844024`, `136a76ef35bb999f1e3aa6d257249cfc54be4649`, `676f0439ac3a236ab9e0f608fd019141552f9be7`, `151e389d9d1ce70afac288f68f09fc2bf6fd5556`, `625d08d721f1243962e1e631e5b1615776a9546c`).
- **Alterações apenas no GitHub, branch desenvolvimento-v19**. Nenhuma alteração de banco ou produção. Mudanças não aparecem no ZIP local até nova cópia; ainda não testadas com a nova interface no navegador.
- Próxima ação: obter números efetivos de dias por contrato para urbano/rural e tipo de ocorrência e decidir se SLA é pausado na garantia. Só então desenvolver RPC de administração de regras e teste por chamado; após isso, atualizar a cópia local e homologar resultados.

## SQL 59 — SLA padrão provisório 2/5 dias corridos, editável (05/11/2026)

- Usuário definiu **2 dias corridos para chamadas urbanas (48h)** e **5 dias corridos para rurais (120h)**, sujeitos à futura alteração. **Não definiu alertas**.
- Criado `sql/v19/59_SLA_PADRAO_DIAS_CORRIDOS_SEGURANCA_HOMOLOGACAO.sql` na branch `desenvolvimento-v19`: o SQL exige consórcios fictícios Alfa/Beta e duas garantias 57 concluídas, para impedir aplicação em V18/produção; instala `v19_salvar_sla_padrao(uuid,integer,integer)` com permissão master/gestor do próprio consórcio autenticado, lock de linha, trilha administrativa e escrita por RPC sem concessões de UPDATE/INSERT direto ao navegador. Inicializa uma única regra `PADRAO_GERAL` **apenas no consórcio Alfa** como urbano 48h, rural 120h e alertas `NULL` (não inventar intervalos). Repetir a migration lança erro. **Ainda não executado pelo operador**.
- Integração de interface preparada: `teste-v19/index.html` adiciona RPC à allowlist autenticada e `teste-v19/v19-config.js` mostra dois campos de dias inteiros (1–365) com confirmação e salvamento via RPC; demais regras permanecem somente para leitura. Correções passaram validação sintática de JavaScript, **mas não foram testadas por navegador nem pelo banco**.
- SQL 59 **não altera `chamados.sla_horas` existentes, não altera chamados concluídos, nem instala automaticamente atribuição do prazo para novos chamados**. Esse último mecanismo será integrado ao fluxo seguro de criação de chamados V19, ainda pendente. Por enquanto, chamadas antigas sem prazo continuam como "SLA não apurável", corretamente.
- Próximo passo operacional único: executar SQL 59 **uma vez no projeto V19 de homologação** pelo SQL Editor e enviar resultado da consulta diagnóstica (8 verificações). Não precisa baixar o ZIP até terminarmos validação do backend.

## SQL 59 — execução confirmada no projeto de homologação (05/11/2026)

- Operador enviou CSV do diagnóstico do `sql/v19/59_SLA_PADRAO_DIAS_CORRIDOS_SEGURANCA_HOMOLOGACAO.sql` com **8/8 OK**:
  1. Projeto Alfa V19 encontrado;
  2. Regra `PADRAO_GERAL` única para Alfa;
  3. Urbano 48 horas = 2 dias corridos;
  4. Rural 120 horas = 5 dias corridos;
  5. Alertas `NULL`, sem pressupor valores;
  6. RPC de edição executável por `authenticated`;
  7. RPC de edição negada a `anon`;
  8. Escrita direta da tabela SLA negada a `authenticated`.
- **Aprovado: instalação/diagnóstico SQL59.** Não afirmar ainda que a edição por perfil autorizado no navegador ou aplicação automática de SLA a chamados novos foram testadas.
- Próximo teste: obter o ZIP atualizado da branch `desenvolvimento-v19` e abrir `teste-v19/index.html` como **Gestor Consórcio Alfa**. Navegar até SLA e verificar regra geral **2 e 5 dias** e os controles para editar, sem gravar nesta primeira conferência. Pode exigir reinserir a chave `sb_publishable_` (somente no navegador) porque o cache usa `sessionStorage`.
- Atenção: o SLA dos 8 chamados antigos permanece "não apurável" porque foram criados antes da regra, e a integração de atribuição automática futura ainda não foi instalada.

## SLA — leitura e controles exibidos no navegador (05/11/2026)

- Print recebido do operador logado como **Gestor Consórcio Alfa**, acessando a versão local atualizada `teste-v19/index.html` → menu **SLA**.
- Na interface, consórcio **TESTE V19 - Consórcio Alfa** e regra `Padrão geral` exibem **urbano 2 dias corridos**, **rural 5 dias corridos**, alertas em branco (—), campos para edição e botão **Salvar prazos gerais** visíveis para esse perfil.
- **Aprovado: exibição/leitura e disponibilidade de controles de edição**; captura não prova ainda gravação pela RPC. Teste seguinte: manter 2 e 5, clicar Salvar, aceitar confirmação, enviar resultado; depois recarregar com F5 para conferir persistência. NÃO alterar os prazos provisórios nesta etapa.

## SLA — gravação e persistência pela interface do gestor (05/11/2026)

- Operador confirmou que **Gestor Consórcio Alfa** clicou em `Salvar prazos gerais`, aceitou a confirmação e recebeu **mensagem de sucesso** do aplicativo, usando prazo **urbano 2 dias corridos** e **rural 5 dias corridos**.
- Operador posteriormente informou que os valores **permaneceram após F5**, confirmando persistência pela interface. Não houve print posterior ao F5 neste turno; evidência é o relato do operador.
- **Aprovado: gravação autorizada e persistência** para o perfil Consórcio Alfa. Permanecem por verificar: perfil Master, bloqueio de outros perfis por JWT e isolamento de consórcios sem autorização. A regra ainda não é automaticamente aplicada aos chamados criados.
- Próximo teste de interface (somente leitura): login no perfil **Master**, acessar o menu SLA e observar se pode selecionar Consórcio Alfa e se a tabela apresenta os valores 2/5 dias, sem salvar nem modificar nada.

## SLA — teste de gravação pelo perfil Master (05/11/2026)

- Usuário enviou captura da tela de **Administrador Master**, consórcio `TESTE V19 - Consórcio Alfa`, regra geral `2 dias urbanos / 5 dias rurais` e campos de edição habilitados.
- Ao ser solicitado a clicar em `Salvar prazos gerais` mantendo 2 e 5, o usuário respondeu **"sim"** à pergunta sobre a mensagem de sucesso. **Gravação pelo Master confirmada pelo relato do operador**.
- A captura posterior mostra 2/5 na tela, mas não permite comprovar sozinha novo F5; **persistência do Master após recarregamento ainda aguarda confirmação**.
- Não houve alteração de prazos, como previsto no roteiro. Não interpretar esse teste como prova de isolamento negativo dos demais perfis.
- Próxima ação: F5 no Master, abrir SLA e confirmar que 2/5 persistem; em seguida testar bloqueio para perfil sem direito de edição.

## SLA — persistência Master confirmada após F5 (05/11/2026)

- Operador respondeu "sim" após ser solicitado a pressionar F5 no login **Administrador Master** e verificar os prazos em **SLA**.
- Confirmado por relato do operador: regra `PADRAO_GERAL` no Consórcio Alfa permaneceu **urbano 2 dias corridos** e **rural 5 dias corridos**, após salvar e recarregar.
- **Aprovado: persistência Master após F5.** Em conjunto com a homologação anterior do Gestor Consórcio Alfa, os dois perfis privilegiados conseguiram gravar e persistir valores inalterados via interface.
- Próximo teste único: login **Empresa Alfa B**, observar se o menu `SLA` é oferecido; captura de tela; não gravar. Isso é apenas teste visual de autorização, não substitui teste negativo de RPC com JWT de empresa.

## SLA — persistência do Master e edição oculta para Empresa Alfa B

- Em 05/11/2026, operador confirmou por mensagem **"sim"** que, após F5 no perfil Master, os prazos gerais Alfa permaneceram **2 dias corridos urbano / 5 dias corridos rural**. Evidência declarada pelo operador.
- Print posterior do usuário com login **Empresa Alfa B** no menu SLA mostra regra `PADRAO_GERAL` de Consórcio Alfa, valores 2/5, **sem campos de alteração e sem botão Salvar**. **Aprovado isolamento de edição na interface para perfil Empresa.**
- Não inferir bloqueio backend apenas desse print; o `v19_salvar_sla_padrao` verifica os perfis no PostgreSQL, mas deve ser submetido a ensaio negativo com JWT real da empresa sem alterar dados.
- Próximo teste visual sugerido: perfil **Técnico Garantia Alfa**, menu SLA, certificar controles de edição ausentes.

## SLA — consulta sem edição pelo Técnico Garantia Alfa (05/11/2026)

- Evidência: screenshot do operador autenticado como `Tecnico Garantia Alfa` exibindo `Configuração de SLA` do `TESTE V19 - Consorcio Alfa`.
- Regra geral lida do banco: **2 dias corridos urbano, 5 dias corridos rural**. Alertas sem definição.
- **Sem campos de edição e sem botão Salvar**: aprovado controle de interface para o perfil garantia.
- Isto **não prova o bloqueio de uma chamada REST direta** por JWT deste perfil; o backend `v19_salvar_sla_padrao` tem restrição estática por `master`/`consorcio`, ainda sem teste negativo de execução com JWT real.
- Testes positivos: gravação e persistência por Master e Gestor Consórcio Alfa confirmadas pelo operador. Testes negativos de interface: Empresa Alfa B e Técnico Garantia Alfa aprovados.

## SLA — teste de negativa da RPC sem gravação preparado (05/11/2026)

- Print do `Técnico Garantia Alfa` na tela SLA: pode ler regra `PADRAO_GERAL` (2 dias urbanos e 5 rurais); **não há campos de edição nem botão Salvar**. Aprovada restrição visual.
- Criado diagnóstico de permissão exclusivamente para interface `teste-v19/v19-config.js` da branch `desenvolvimento-v19` (commit `5be514e13e9013aff7382a62e8d8a3ed123aca2a`).
- Para perfis não administradores, botão **Testar bloqueio de edição pelo banco** envia tentativa real à RPC `v19_salvar_sla_padrao`, fornecendo `p_urb_dias=0`, `p_rur_dias=0`. Essa combinação é **sempre inválida** e nunca pode produzir atualização, mesmo diante de falha de autorização. SQL 59 checa a permissão do usuário **antes** do valor dos dias, portanto resposta `PERFIL_NAO_AUTORIZADO` ou `CONSORCIO_NAO_AUTORIZADO` indica recusa pelo perfil. Resposta de validação `PRAZO_EM_DIAS_INVALIDO` revela que a verificação de permissão foi ultrapassada e demanda investigação, sem alteração de prazo.
- A UI diferencia **APROVADO**, **inconclusivo** e **falha crítica**. Esta alteração está no GitHub, não no ZIP local; foi conferida sintaxe JavaScript, mas **não testada ainda com sessão JWT do usuário**.
- Próximo passo único: atualizar ZIP V19, fazer login `Técnico Garantia Alfa`, entrar em SLA e clicar **Testar bloqueio de edição pelo banco**, enviar captura do resultado. Não compartilhar chave pública, JWT ou senha no chat.

## SLA — teste negativo com JWT do Técnico Garantia Alfa aprovado

- Operador enviou screenshot com login **Técnico Garantia Alfa**, página `SLA`, regra `PADRAO_GERAL` exibindo urbano **2 dias corridos** e rural **5 dias corridos**.
- O novo diagnóstico `Testar bloqueio de edição pelo banco` mostra o resultado verde: **“APROVADO: o Supabase recusou a RPC para este perfil.”**
- O código do diagnóstico envia `p_urb_dias:0`/`p_rur_dias:0`, valores sempre inválidos, e só marca APROVADO se a resposta inclui `PERFIL_NAO_AUTORIZADO` ou `CONSORCIO_NAO_AUTORIZADO`. A validação de perfil antecede a de prazo na RPC SQL59; nenhum prazo é gravável nesse teste.
- **Aprovado para esse JWT:** bloqueio de edição por perfil Garantia pelo backend, além do bloqueio visual já observado. Não generalizar para outros perfis ou consórcios sem teste.
- Próximo teste: **Empresa Alfa B** no mesmo ZIP atualizado, página SLA, clicar botão de diagnóstico e capturar resposta; não alterar prazos.

## SLA — teste negativo com JWT da Empresa Alfa B aprovado

- Captura de tela do operador logado como `Empresa Alfa B`, na V19 de homologação, mostra `Padrão geral` com **2 dias urbanos/5 dias rurais** e nenhum campo de edição de SLA.
- O botão de diagnóstico `Testar bloqueio de edição pelo banco` foi executado; a tela apresentou **“APROVADO: o Supabase recusou a RPC para este perfil.”**
- Este diagnóstico envia `p_urb_dias=0` e `p_rur_dias=0` para a `v19_salvar_sla_padrao`; a UI somente considera aprovado quando o erro da RPC é `PERFIL_NAO_AUTORIZADO` ou `CONSORCIO_NAO_AUTORIZADO`. O SQL 59 verifica o perfil antes de validar os valores, e 0 não poderia ser salvo.
- **Aprovada negativa por JWT Empresa Alfa B**; somada à negativa por JWT Técnico Garantia Alfa, e aos testes positivos de Master e Gestor Consórcio Alfa com persistência.
- O isolamento de gestor de outro consórcio e a atribuição automática da regra `PADRAO_GERAL` a novos chamados seguem **pendentes**. O teste não comprova todos os papéis ou todos os consórcios.

## SLA — Master consultou Consórcio Beta sem herdar regra do Alfa (05/11/2026)

- Captura de tela: usuário autenticado **Administrador Master** na opção SLA, consórcio selecionado **TESTE V19 - Consórcio Beta**; a tabela informa **"Nenhuma regra de SLA cadastrada"** e não apresenta 2/5 dias do Alfa.
- **Aprovado:** segregação de leitura de configuração entre os consórcios na interface Master. Não equivale a teste de gestor Alfa tentando editar Beta via RPC com seu JWT.
- Encontrado erro de UX: aviso sugeria executar novamente SQL59 apesar de ele só criar a regra de Alfa e falhar se reexecutado. Corrigido `teste-v19/v19-config.js` na branch desenvolvimento-v19 (commit `f7225ad7df06e95fa1d5c3daf91ffa5b6fa69ffe`) para avisar que Beta não tem regra própria e não orientar repetição do SQL59. **Mudança ainda não presente na cópia ZIP local do usuário.**
- Próximo passo visual único: entrar como **Gestor Consórcio Alfa**, abrir menu SLA, expandir seletor de consórcios e observar se oferece apenas o Alfa; não alterar valores. O isolamento de escrita por JWT de consórcio não será considerado provado apenas com esse teste de interface.

## SLA — Gestor Alfa vê apenas o próprio consórcio no seletor (05/11/2026)

- Print do operador, autenticado como **Gestor Consórcio Alfa**, no menu SLA, mostra seletor aberto com **apenas uma opção**: `TESTE V19 - Consorcio Alfa`.
- Valores permanecem em **2 dias corridos urbano / 5 dias corridos rural**; campos de edição e botão Salvar para o próprio consórcio.
- **APROVADO: isolamento de seleção e leitura de consórcios no frontend** para Gestor Alfa. Não inferir isolamento de escrita por JWT para consórcio Beta a partir da lista do seletor; o backend bloqueia esse caso pelo código SQL59, mas aguarda teste com identidade real.
- Próximo ensaio seguro: obter UUID do Consórcio Beta por consulta **somente leitura** no SQL Editor e usá-lo em tentativa com dias inválidos para testar o bloqueio `CONSORCIO_NAO_AUTORIZADO`, sem alterar regras.

## SLA — teste negativo entre Gestor Alfa e Consórcio Beta preparado (05/11/2026)

- Operador consultou no Supabase V19 (somente leitura) o identificador de consórcio fictício Beta, `9674d593-7d2b-44da-8d4d-97070bc95aca` (`teste-v19-beta`).
- Adicionado à interface na branch `desenvolvimento-v19`, commit `1e4e280e7efd8d1c0164d3ab37c6579cae2fa6fe`, botão exclusivo do perfil `consorcio`: **Testar bloqueio entre consórcios**.
- O diagnóstico faz uma requisição autenticada `v19_salvar_sla_padrao` passando `p_consorcio_id` do Beta e prazos `p_urb_dias=0`, `p_rur_dias=0` (inválidos por design). A RPC deve retornar `CONSORCIO_NAO_AUTORIZADO` ao Gestor Alfa, antes de avaliar os prazos. **Nenhum UPDATE é possível com 0/0 dias** mesmo diante de falha da checagem de consórcio.
- Somente a resposta `CONSORCIO_NAO_AUTORIZADO` é aceita pelo diagnóstico como aprovação; outra exceção resulta em **inconclusivo**. Alteração submetida e verificada sintaticamente, **não testada ainda com JWT real no navegador**.
- Próximo passo: baixar novo ZIP branch V19, fazer login como Gestor Consórcio Alfa, abrir SLA, clicar o novo botão e enviar print do retorno. Não executar SQL59 novamente nem alterar dados do banco.

## SLA — JWT do Gestor Alfa bloqueado ao tentar editar Beta (05/11/2026)

- Screenshot da V19 com sessão **Gestor Consórcio Alfa**, tela SLA, regra geral **2 dias urbanos / 5 dias rurais**, botão de diagnóstico executado `Testar bloqueio entre consórcios`.
- Resultado mostrado na tela: **“APROVADO: o Supabase bloqueou a edição de outro consórcio.”** No código de teste, essa indicação só ocorre após o erro `CONSORCIO_NAO_AUTORIZADO` na RPC `v19_salvar_sla_padrao`, para o UUID Beta `9674d593-7d2b-44da-8d4d-97070bc95aca` com os dias inválidos 0/0.
- **Aprovado cenário negativo com JWT real do gestor de outro consórcio.** O teste usa 0/0, por isso não altera prazos mesmo diante de falha inesperada. A visualização continua sem oferecer Beta no seletor do gestor.
- A etapa de segurança da regra geral SLA está validada para os perfis exercitados: Master e Gestor Alfa podem salvar; Empresa Alfa B e Garantia Alfa não podem; Gestor Alfa não pode salvar no Beta. Não extrapolar a conclusão para todos os consórcios e todas as funções da aplicação.
- A **atribuição automática a novos chamados ainda não está implementada**, e exige cuidado com `guard_chamados`: no fluxo de INSERT de prefeitura/empresa, `NEW.sla_horas` não pode ser definido pelo cliente. Um trigger executado na ordem errada pode bloquear a abertura legítima. Assim, antes de modificar o backend, foi preparado o diagnóstico **SQL 60 (somente leitura)** no caminho `sql/v19/60_DIAGNOSTICO_ROTAS_CRIACAO_E_GATILHOS_SLA_SOMENTE_LEITURA.sql` (commit `55ede1f4acad65666445dd7090c64f2b1b14946f`).
- **Próximo passo para operador:** executar somente o SQL 60 no projeto de homologação V19, enviar a tabela `grupo,objeto,resultado,detalhe`. Sem alterações de dados, sem repetir SQL59.

## SQL 60 conferido — SQL 61 preparado para atribuição automática de SLA

- Usuário retornou a saída do SQL 60 no Supabase V19: consórcios Alfa e Beta encontrados; um único trigger listado, `trg_v19_historico_chamados` **AFTER UPDATE**; no catálogo das funções consultadas apareceu apenas `v19_salvar_sla_padrao` (**SECURITY DEFINER**). Isso indica que `guard_chamados` e `abrir_chamado_publico` **não foram encontrados**; não presumir as rotas antigas instaladas.
- Regras confirmadas: Alfa `PADRAO_GERAL` urbano 48h/rural 120h, Beta sem regra; alertas não definidos. Chamados existentes: Alfa 8 (0 com SLA), Beta 1 (0 com SLA). Não retroagir.
- Criado `sql/v19/61_SLA_AUTOMATICO_NOVOS_CHAMADOS_HOMOLOGACAO.sql` na branch `desenvolvimento-v19`, commit `9867f25f09dc8e5ddee66519a9c6e506347f59fa`. Ainda **não executado pelo operador**.
- SQL61 possui proteções do ambiente V19, exige os resultados e regras do SQL59/60 e bloqueia execução repetida, instalação sobre outro gatilho BEFORE INSERT ou com GRANT de INSERT aos clientes. Instala **BEFORE INSERT** em `chamados` e função `v19_sla_na_abertura()` de execução direta revogada; escolhe regra por tipo do mesmo consórcio ou `PADRAO_GERAL`, respeita `area`, **substitui prazos informados por cliente** pelo valor da regra do banco. Para consórcio sem regra, guarda `NULL`.
- Autoteste do SQL61 insere de forma transitória três chamados (Alfa urbano 48h, Alfa rural 120h, Beta sem SLA), confere resultados e força reversão da subtransação para não manter fixtures. O SQL 61 não mexe nos **9 chamados antigos**, não regrava histórico e não concede INSERT direto nem cria novas rotas públicas.
- Limitação: instalar gatilho **não torna o botão “Novo chamado” operacional**. Abertura autenticada/pública exige RPC dedicada e homologação específica porque as rotinas antigas não foram encontradas. O trigger será válido para os fluxos seguros futuros; deve reavaliar ordem de triggers antes de adicionar novos BEFORE INSERT.
- Próxima ação: executar SQL 61 **somente no Supabase V19 de homologação**, uma vez, enviar tabela final de oito verificações. Nenhum ZIP novo necessário agora.

## SQL 61 — 8/8 aprovado; SQL 62 abertura interna segura preparada

- Operador retornou 8 verificações `OK` do SQL61 no projeto V19: ambiente Alfa/Beta, autotestes urbano 48h / rural 120h / Beta sem regra, função trigger inacessível a anon e authenticated, histórico preservado, INSERT direto negado, nenhum chamado de teste persistido e trigger BEFORE INSERT de SLA instalado.
- **Aprovada instalação e testes automatizados SQL61**; não afirmar que a interface já abriu chamados.
- Inspeção da V19 verificou que `vNovoChamado()` já traz formulário interno, mas `sbSaveChamado` tentava escrever direto em `chamados`, bloqueado pela allowlist; `abrir_chamado_publico` segue inexistente e o portal público não foi liberado.
- Preparado `sql/v19/62_ABERTURA_INTERNA_SEGURA_SLA_HOMOLOGACAO.sql` (commit `d4ed135dfcb3fd94ccc80e12cedd467782c8a4dd`) **ainda não executado**. Cria RPC `v19_criar_chamado_interno(uuid,text,text,text,text,integer,text,uuid,numeric,numeric,text)`: aceita só JWT ativo nos perfis Master, Consórcio, Prefeitura (sua cidade) e Empresa (cidades atribuídas, própria empresa); proíbe perfil Garantia/anon e atribuição cruzada; calcula consórcio e protocolo pelo servidor; histórico inicial inserido na mesma transação; sla_horas automaticamente preenchido pelo gatilho SQL61; nenhum GRANT direto para INSERT/UPDATE/DELETE.
- O SQL62 contém 8 verificações estruturais finais e **não cria chamados de teste nem altera os existentes**. A validação com JWT real deverá ocorrer em fase posterior pela interface.
- A branch `desenvolvimento-v19` contém frontend de abertura interna atualizado, commits `3bcefa438b89f15fd2c67874838075c7c68c7ae2` e `96306b2cc526fd48ca4e185a2dbfb8847a570fe8`: botão Novo chamado habilitado para perfis elegíveis, envio via RPC dedicada, UUID de cidade no seletor, protocolo/data/SLA devolvidos pelo Supabase, sem escrita de histórico cliente, geocodificação preservada e proteção contra duplo clique. Sintaxe dos scripts JS validada, **mas ainda não testados no navegador**.
- **Não habilitado:** portal público, alteração administrativa genérica de chamados, foto, tratamento completo de idempotência em falha de rede, e demais fluxos que ainda requerem RPC. Não declarar a V19 pronta para produção.
- Próximo passo único: operador executar uma vez SQL62 **somente no projeto Supabase V19 de homologação**, compartilhar as 8 verificações; depois baixar ZIP atualizado e criar **um** chamado urbano sintético na interface para testar gravação de 48h, histórico e F5. Não reutilizar V18/produção.

## Interface — formulário interno abre para Gestor Consórcio Alfa (05/11/2026)

- Operador enviou captura do `Novo chamado interno` logado como **Gestor Consórcio Alfa** após aplicação do SQL62 (8/8).
- Formulário abre e mostra `Municipio Alfa 1`, área `Urbana`, tipo `Lâmpada apagada` (selecionado), quantidade `1` e `Sem atribuição` de empresa; campos de bairro, endereço, observações e GPS visíveis.
- **Aprovado: renderização e abertura do formulário interno** para o gestor. Nenhum chamado novo confirmado ainda. O quadro de metadados de sessão apresenta `Organização —` apesar do perfil e responsável aparecerem corretos; pendência cosmética a conferir.
- Operador orientado a criar **um único chamado sintético urbano** em Município Alfa 1, sem endereço/GPS/foto, com `Homologação V19` no bairro e observações claras de teste. Esperados: status Recebido, SLA 48h, histórico inicial atômico. Não repetir o clique em caso de erro; analisar a resposta antes de tentar novamente.

## V19 — primeira abertura interna na interface e SLA pendente de diagnóstico (05/11/2026)

- Print do Gestor Consórcio Alfa na lista de Chamados após usar `Novo chamado`: **9 chamados**, sendo 8 anteriores e **1 novo** com protocolo gerado pelo servidor começando em `V19I-`; cidade `Municipio Alfa 1`, bairro `Homologação V19`, tipo `Lâmpada apagada`, status `Recebido`, origem `Interno`, abertura `05/11/2026 13:41`. O retorno automático à lista é comportamento do frontend após confirmação da RPC.
- **Aprovado parcialmente:** abertura e listagem de novo chamado via interface. O quadro SLA do novo chamado mostra **`SLA não apurável`**, apesar da regra geral de Alfa ser 48h e SQL61 ter confirmado a atribuição no autoteste. Não afirmar atribuição de SLA para este registro até verificar coluna `chamados.sla_horas` e datas.
- Recomendado **não repetir criação nem alterar registros**, e executar consulta SQL SELECT somente leitura filtrando `consorcio.slug='teste-v19-alfa'` e `origem='Interno'`; verificar `sla_horas`, `area`, `created_at`, `sla_pausado`, `completed_at`, contagem de histórico. Se `sla_horas=48`, investigar `window.v19StatusSLA` e carregamento de `v19-relatorios.js`; se NULL, investigar SQL61/SQL62/trigger efetivo.
- **Não testar outro chamado enquanto divergência entre banco e interface não for resolvida.**

## SLA — validação positiva do banco 48h e correção de dependência na interface

- O operador executou consulta SQL somente leitura para o primeiro chamado interno `V19I-B34E69091ABE419797D63A0D6BC0A0A2`: `Urbana`, `Recebido`, `sla_horas=48`, `prazo_dias=2`, `created_at=2026-11-05 16:41:13.209307+00`, `sla_pausado=false`, **1 evento de histórico**.
- **Aprovados no banco:** criação da RPC SQL62 com status Recebido, atribuição de SLA urbano pelo trigger SQL61, e histórico inicial singular. Nove chamados em Alfa listados após a operação, dos quais um novo. Não foi pedido criar outro.
- **Pendência de interface observada:** listagem mostrava `SLA não apurável` para o novo chamado com 48 horas válidas, sugerindo dependência/ordem de carregamento da função `window.v19StatusSLA` fornecida pelo script de relatórios. Não há diagnóstico de console no navegador para provar a causa exata; não alegar causa determinada.
- **Correção de robustez preparada na branch `desenvolvimento-v19`**: agora `teste-v19/index.html` inicializa a função compartilhada `window.v19StatusSLA` na própria página antes da renderização, independente do arquivo auxiliar (commit `610d297bcfdcd0cbfe6f851faadf5d5fc2f09525`). O módulo `teste-v19/v19-relatorios.js` reaproveita essa mesma função (commit `6ae6b5abdbf01a9c5ece4750772209af71f5e0f2`).
- Validada sintaxe JS dos dois arquivos e cinco cenários isolados de cálculo: urbano 48h, rural 120h, sem SLA, pausado, atrasado. **Ainda não verificado no Chrome do operador.**
- Próxima tarefa única: baixar ZIP V19 atualizado, entrar Gestor Consórcio Alfa, abrir `Chamados`, pressionar F5 e conferir SLA do chamado **já criado**. Nenhum SQL adicional, nenhuma duplicação de chamado, nenhuma alteração no banco. V18/produção intactos.

## SLA automático urbano na UI — aprovado com F5 e prazo restante (05/11/2026)

- Operador enviou print em `Chamados`, logado como **Gestor Consórcio Alfa**, após baixar ZIP com correção do cálculo `window.v19StatusSLA`.
- Primeiro chamado interno `V19I-B34E69091ABE419797D63A0D6BC0A0A2` com status **Recebido**, origem Interno e SLA destacado em verde **“✓ 1,99 dias restantes (estim.)”**.
- Consulta SQL anterior confirmou `sla_horas=48`, área Urbana, `sla_pausado=false`, uma entrada em `chamado_historico`.
- Lista mantém **9 chamados**, sem duplicação após F5; demais 8 sem SLA retroativo permanecem “SLA não apurável”, como previsto.
- **APROVADO**: criação interna urbana, SLA automático no banco, apresentação em dias corridos e persistência após reload. 1,99 dias é saldo estimado desde a abertura, não erro de prazo.
- Problema visual menor identificado no rótulo curto do protocolo gerado `V19I-` (renderização com prefixo adicional) — não afeta o UUID nem o valor armazenado; corrigir em revisão futura da UI, preservando protocolo integral no banco.
- **Próximo teste:** criar apenas um novo chamado sintético **Rural** no Consórcio Alfa via mesma UI, confirmar 120 horas (5 dias) e 1 histórico no SQL; não alterar regras, não usar registros reais, evitar segundo clique.

## Pendência UX — prazo SLA em dias inteiros (05/11/2026)

- Responsável solicitou que a visualização do SLA deixe de apresentar decimais (`1,99 dias restantes`), preferindo contagem **em dias inteiros**, como `2 dias`, `1 dia`, `0 dias`.
- **Pendente de implementação após testes atuais**, para não obrigar novo ZIP durante a homologação do chamado rural.
- Manter armazenamento, vencimento e verificação do SLA com precisão de timestamp/horas no banco. Ajustar apenas apresentação e esclarecer limiares de arredondamento, especialmente prazo inferior a 24h e transição para atraso, para não transmitir prazo enganoso. Conferir listagem, detalhes e relatórios.
- O próximo teste em andamento continua sendo o chamado **Rural Alfa**, esperado SLA `120 horas` = `5 dias corridos`, com registro único de histórico.

## SLA rural — novo chamado criado, prazo na UI ainda não apurável (05/11/2026)

- Print do Gestor Consórcio Alfa após registrar o segundo chamado sintético interno: tabela exibe **10 chamados**, primeiro registro recente `Municipio Alfa 1`, bairro `Homologação V19 Rural`, tipo `Lâmpada piscando`, status `Recebido`, origem `Interno`, abertura 05/11/2026 13:53 (BRT).
- **Criação e leitura do novo registro aprovadas visualmente**. A coluna SLA do novo rural exibe `SLA não apurável` embora a configuração Alfa tenha `rur_prazo=120` (5 dias corridos). O chamado urbano anterior permanece com `1,99 dias restantes`.
- **Não aprovar ainda SLA rural**. Distinguir hipótese de erro de atribuição no banco vs erro de exibição na interface com SELECT de somente leitura por `consorcio.slug='teste-v19-alfa'`, `origem='Interno'`, `area='Rural'`, retornando `sla_horas`, prazo dias, data de abertura, pausa, histórico. Não criar outro chamado nem reexecutar migrations.
