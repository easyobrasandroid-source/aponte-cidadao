# V19 — Regra revisada de conclusão da Garantia LED

Atualizado em 2026-11-04. **Somente homologação.**

## Regra funcional

Um chamado com `status = 'Aguardando Garantia LED'` e `garantia_tipo = 'LED'` pode ser concluído por:
1. Usuário ativo do perfil **garantia** vinculado ao mesmo consórcio do chamado;
2. Usuário ativo do perfil **empresa** quando o chamado **já está atribuído à sua empresa**, o consórcio é o mesmo, a empresa está ativa e atende à cidade ativa desse chamado.

O mero atendimento à cidade **não autoriza** a empresa a concluir um chamado atribuído a outra empresa. Prefeitura, Master e empresas externas não usam esta RPC específica. Uma chamada concluída não pode ser concluída novamente.

## Implementação

- `sql/v19/18_PERMITIR_CONCLUSAO_EMPRESA_RESPONSAVEL_E_GARANTIA_HOMOLOGACAO.sql` substitui somente `public.v19_concluir_garantia(uuid)` criada pelo SQL 17.
- O SQL 17 continua sendo pré-requisito para o trigger `trg_v19_historico_chamados`.
- Não concede `UPDATE` direto para `authenticated` ou `anon`.
- Todas as conclusões passam pelo servidor, com autenticação Supabase, `FOR UPDATE` e histórico persistente.

## Mudança nos testes

O antigo teste 18 com **Empresa Alfa A** tinha resultado esperado 403, mas **não é mais válido** após a instalação do SQL 18, porque Alfa A é justamente a empresa responsável pelo chamado. Usar **Empresa Alfa B** ou **Empresa Beta A** para verificar a negativa.

### Sequência segura
- [ ] Executar SQL 18 somente no novo projeto de homologação.
- [ ] Conferir 4 resultados OK e que o chamado `V19-TESTE-GARANTIA-ALFA-1` ainda aguarda Garantia.
- [ ] Empresa Alfa B: tentativa de conclusão deve retornar 403, sem alterar status/histórico.
- [ ] Empresa Beta A: tentativa de conclusão deve retornar 403, sem alterar status/histórico.
- [ ] Empresa Alfa A: deve conseguir concluir seu chamado em garantia e gerar **uma** transição de histórico.
- [ ] Repetir conclusão pela mesma conta ou Garantia: deve falhar sem histórico duplicado.
- [ ] Criar um **novo** chamado em garantia para testar o caminho autorizado do perfil Garantia Alfa.
- [ ] Confirmar que não existe edição direta de status pelo navegador.

**Não executar os testes de conclusão positiva contra o mesmo chamado duas vezes.**
