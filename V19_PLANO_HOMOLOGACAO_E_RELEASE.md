# Aponte Cidadão V19 — Runbook de homologação e critérios de liberação
Atualizado: 2026-11-03. Branch: `desenvolvimento-v19`.

## Bloqueio principal
**Não executar migrations no Supabase de produção, não fazer merge em main e não apontar a V19 para chaves/URL de produção.** Uma branch separada no GitHub não isola o banco.

## Portões de aprovação (G0–G7)

### G0 — Inventário e preparação
- [ ] Confirmar que `main`/V18 permanece sem alterações V19.
- [ ] Registrar projeto/URL de homologação sem publicar segredos.
- [ ] Confirmar origem do esquema-base (snapshot compatível da V18 ou esquema validado).
- [ ] Identificar quais tabelas/funções já existem e quais migrations são aplicáveis.
- [ ] Criar cópia de segurança e testar procedimento de restauração.
- [ ] Separar pelo menos dois consórcios, duas empresas e municípios de teste.
- [ ] Confirmar Auth, Storage e políticas esperadas no ambiente de homologação.
**Saída:** ambiente isolado e inventário assinado.

### G1 — Migração controlada
- [ ] Auditar SQL antes da execução: compatibilidade de tabelas/colunas, triggers, funções e grants.
- [ ] Executar `sql/v19/00_diagnostico_integridade_estoque_somente_leitura.sql` na homologação.
- [ ] Escolher **um** roteiro de migração coerente. O pacote `08_INSTALACAO_CONSOLIDADA_SOMENTE_HOMOLOGACAO.sql` consolida 03-transacional até 07; **não** misturar com o caminho alternativo 03-stage1 sem análise.
- [ ] Rodar o 08 somente na homologação, após verificar pré-condições.
- [ ] Rodar `09_auditoria_permissoes_SOMENTE_LEITURA.sql` e revisar resultados.
- [ ] Verificar rollback em caso de erro e testes de integridade pós-migração.
**Saída:** banco V19 íntegro, RPCs, policies e Storage verificados.

### G2 — Segurança de acesso e segregação
- [ ] Testar sessões reais com Master, Consórcio A/B, Prefeitura, Empresa A/B e Garantia.
- [ ] Testar acesso direto à REST API e RPCs (não somente ocultação dos botões).
- [ ] Empresa A não pode ler/alterar chamado, telefone, foto ou estoque privativo da Empresa B.
- [ ] Prefeitura só acessa cidade/consórcio autorizados.
- [ ] Garantia só conclui casos elegíveis e gera histórico auditável.
- [ ] Assumir chamado usa concorrência (duas empresas tentando simultaneamente): exatamente uma vence.
- [ ] Consulta pública por telefone continua bloqueada sem verificação apropriada.
**Saída:** zero falhas críticas de autorização.

### G3 — Fluxos operacionais e consistência
- [ ] Abrir, atualizar, atribuir, concluir, reabrir chamado; verificar timestamps/status e logs.
- [ ] Gestão de equipes persiste após F5 e sessão nova.
- [ ] Materiais: cadastrar, movimentar, consumir, consultar saldo e histórico.
- [ ] Saldo nunca negativo; transações concorrentes não duplicam consumo.
- [ ] Fotos: upload, metadados, leitura após F5, exclusão autorizada, bloqueio cruzado.
- [ ] Nenhum seed/localStorage serve como fonte de verdade operacional.
**Saída:** todas as gravações confirmadas em banco.

### G4 — Regras de negócio e qualidade visual
- [ ] Dashboard com seleção de período/cidade e contagens reconciliadas ao banco.
- [ ] Excel/PDF reproduzem filtros ativos; não confundem conclusão com cumprimento de SLA.
- [ ] SLA canônico validado para pausas, reabertura, dias úteis/feriados conforme contratos.
- [ ] Mapa mostra GPS real ou sinaliza ausência; não inventar coordenadas.
- [ ] Portal público obedece configurações persistidas e proteção de consulta.
- [ ] Interface responsiva, erros claros, sem solicitações duplicadas.
**Saída:** métricas e fluxos de usuário confiáveis.

### G5 — Regressão formal
- [ ] Rodar `node scripts/verificar-v19.mjs` e checar GitHub Actions.
- [ ] Executar 21 requisitos V19 e 38 testes de aceite (registrar evidência por caso).
- [ ] Registrar resultado: passou/falhou/bloqueado, usuário, dados, versão e evidências.
- [ ] Corrigir falhas e repetir toda a regressão afetada.
**Saída:** 100% dos casos críticos aprovados, sem falhas graves abertas.

### G6 — Piloto supervisionado
- [ ] Simular operação multitenant com dados sintéticos (2 consórcios) e todos os perfis.
- [ ] Exercitar indisponibilidade de rede, login expirado, chamadas repetidas e concorrência.
- [ ] Verificar exportações, rotinas e registro de incidentes.
**Saída:** aprovação formal do piloto.

### G7 — Produção controlada
- [ ] Congelar versão e SHA do release.
- [ ] Janela de manutenção, backup/restauração testados e plano de rollback.
- [ ] Comparar esquema real da produção antes de aplicar SQL.
- [ ] Migrar primeiro o banco com compatibilidade V18 preservada; depois frontend planejado.
- [ ] Executar smoke tests e monitorar erros, Auth, Storage, RPCs e auditoria.
- [ ] Publicar somente após aprovação; reverter imediatamente diante de falha crítica.
**Saída:** produção estável, V18 preservada até decisão de corte.

## Bloqueadores identificados nesta revisão
1. O próprio pacote 08 declara dependência de esquema V18 instalado e compatível; não basta ter um Supabase vazio.
2. Não há evidência de execução de migrations em um Supabase isolado, nem testes funcionais com JWTs reais.
3. A alternativa `03_rpc_estoque_stage1_HOMOLOGACAO.sql` e a versão `03_rpc_estoque_transacional_NAO_APLICAR.sql` têm propostas distintas: devem ser reconciliadas antes de executar.
4. O arquivo 09 é **apenas auditoria** e não demonstra, sozinho, isolamento entre tenants.
5. Regras de SLA (dias úteis, pausas, feriados e reabertura) não estão homologadas.

## Registro de execuções
| Gate | Estado | Evidência | Responsável/Aprovação |
| --- | --- | --- | --- |
| G0 | Em andamento | Inventário de arquivos revisado | Pendente |
| G1 | Não iniciado | — | Pendente |
| G2 | Não iniciado | — | Pendente |
| G3 | Não iniciado | — | Pendente |
| G4 | Não iniciado | — | Pendente |
| G5 | Não iniciado | — | Pendente |
| G6 | Não iniciado | — | Pendente |
| G7 | Não iniciado | — | Pendente |
