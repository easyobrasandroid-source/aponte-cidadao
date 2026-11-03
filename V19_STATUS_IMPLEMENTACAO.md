# Aponte Cidadão V19 — quadro verificável de implementação

Atualizado em 2026-11-03. **Branch:** desenvolvimento-v19. `main` (V18) não alterada.

## Código gravado na branch

- [x] Dashboard deixou de mostrar gráficos e tendências fictícias; usa chamados carregados do banco, possui períodos 30/90 dias, histórico ou mês específico e filtro por cidade. Ainda depende de RLS correto e da homologação.
- [x] Consulta dos chamados paginada em blocos de 500 com erro explícito em limite excessivo.
- [x] Tela Empresas restringe a consulta do perfil empresa ao próprio ID e oculta controles de administração; funções de edição também verificam papel. **A proteção definitiva é a RLS pendente.**
- [x] Cadastro de materiais e movimentação manual preparados para usar RPCs transacionais, evitando saldo editado por PATCH simples.
- [x] RPCs `v19_salvar_material` e `v19_movimentar_estoque` propostas em `03_rpc_estoque_stage1_HOMOLOGACAO.sql`. **Não foram instaladas/testadas no Supabase.**
- [x] Telas SLA e Configuração do Portal deixaram de declarar salvamento inexistente. Enquanto a integração definitiva não estiver pronta, aparecem em modo demonstrativo/somente leitura.
- [x] Material de teste e seu estoque excluídos do banco compartilhado com V18, confirmação posterior de duas linhas `EXCLUIDO`.

## Ainda pendente para considerar V19 pronta

- [ ] V19-001: política SELECT de chamados isolando empresa por `empresa_id` e fila resumida para assumir.
- [ ] V19-002: permissão Garantia LED limitada aos chamados atribuídos e conclusão auditada.
- [ ] V19-003: persistência de equipes com recarga real.
- [ ] V19-004: RBAC de empresas comprovado em RLS e persistência, além da proteção de tela.
- [ ] V19-005: SLA correto no mapa, chamados e dashboard, inclusive pausas.
- [ ] V19-006: relatório SLA baseado em prazo real, sem confusão com taxa de conclusão.
- [ ] V19-007: consistência status/conclusão e timestamp.
- [ ] V19-008: exportações Excel/PDF com exatamente os filtros ativos.
- [ ] V19-009: relatórios de estoque a partir de `estoques` e `movimentacoes`, sem seed.
- [ ] V19-010: corrigir % utilizado e não somar unidades heterogêneas.
- [ ] V19-011: upload de fotos com modal estável, objeto Storage + metadado.
- [ ] V19-012: histórico de status persistido pelo servidor.
- [ ] V19-013: fluxo atômico `assumir chamado` para empresas.
- [ ] V19-014: configuração de SLA verdadeiramente gravada por consórcio.
- [ ] V19-015: testes de dashboard e filtros com dados reais (código inicial pronto).
- [ ] V19-016: persistência/configuração do portal e enforcement nas RPCs públicas.
- [ ] V19-017: privacidade de consulta por telefone.
- [ ] V19-018: atraso e GPS real/aproximado no mapa.
- [ ] V19-019: filtros fixos da prefeitura e escopos no servidor.
- [ ] V19-020: validar cadastro de material (RPC e UI) em Supabase de homologação.
- [ ] V19-021: gravações confirmadas no servidor em usuários/empresas/estoque.

## Bloqueios antes de publicar

1. Executar migrations em banco de **homologação isolado**.
2. Migrar chamadas front que ainda escrevem diretamente nas tabelas de estoque e demais módulos para RPCs corretas, e então restringir GRANT/RLS.
3. Testar as 38 condições de aceitação do dossiê; documentar resultados.
4. Publicar caminho de homologação `teste-v19/` apenas depois de garantir que operações esperadas funcionam.
5. Planejar publicação para produção com rollback. V18 usa o banco de produção compartilhado; qualquer migration executada ali afeta também a V18.

## Evidências de verificação

Após cada atualização de `teste-v18/index.html` na branch V19, o script inline principal foi compilado com `new Function` (validação **somente de sintaxe**, não é teste em navegador nem validação de RLS). Última verificação: todos os cinco blocos `script` sem erro de sintaxe. SHAs e commits verificáveis no histórico do GitHub.
