# V19 — Plano de correção do estoque (não aplicar em produção ainda)

**Data:** 2026-11-03. **Branch:** `desenvolvimento-v19`.

## Estado comprovado

- Consulta de pós-limpeza confirma `materiais.id = fc35c185-2a84-476a-9262-97637efc4508` e `estoques.id = 350cd419-6124-4b0d-9526-f0aa674dd365` como **EXCLUIDO**. Foram removidos apenas dois registros de teste, no banco compartilhado com V18. CSV de cópia anterior foi exportado.
- CSV de políticas RLS: `pol_est_wr` em `estoques` permite escrita a todos do mesmo consórcio; `pol_mov_ins` permite incluir movimentos ao consórcio; `pol_cm_wr` em `chamado_materiais` permite ALL sempre que o chamado existe e pode ser lido pelo papel. Essas regras não asseguram baixa atômica/isolamento por empresa.
- `public._pode_estoque(p_consorcio,p_cidade)` aceita uma empresa que atenda à cidade mesmo quando `chamados.empresa_id` pertence a outra empresa.
- RPCs `consumir_material_chamado`, `editar_material_chamado`, `remover_material_chamado` realizam transação do saldo + item + movimento, mas reutilizam `_pode_estoque` com dois parâmetros, sem validar atribuição.
- Na branch V19 atual, `sbSaveMaterial` grava `materiais` e `estoques` diretamente via PostgREST sem preencher `consorcio_id`; `salvarMovimentacao` faz PATCH direto em `estoques` sem registrar linha em `movimentacoes`, embora agora confira a resposta antes de exibir sucesso. `sbBaixaEstoque` ainda faz PATCH direto (verificar se é chamado antes de migrar).
- Última auditoria de integridade anterior à limpeza: 13 linhas em `estoques`, nenhuma duplicada, nenhum saldo negativo, 6 itens em `chamado_materiais`, zero linhas em `movimentacoes`, 1 estoque sem consórcio (o de teste, já excluído).
- Portanto, **revogar UPDATE/INSERT de `estoques` agora quebraria telas atuais** antes de substituir os fluxos do frontend por RPCs transacionais.

## Ordem de implantação

1. Em projeto de homologação separado ou branch de banco isolada, revalidar estrutura/DDL e os dados (script 00).
2. Criar RPC de cadastro e ajuste manual de material/estoque, SECURITY DEFINER, `search_path` fixo, identidade ativa verificada pelo banco, autorização Master/Consórcio e checagem de consórcio. Inserir movimento no mesmo commit que atualizar saldo. Validação de valores finitos, não negativos e consórcio obrigatório.
3. Corrigir as três RPCs de consumo/edição/estorno para exigir `chamado_id`, igualdade `chamados.empresa_id = usuarios.empresa_id` quando perfil Empresa e vínculo de consórcio/cidade, mantendo Master/Consórcio autorizados. Importante: uma empresa não deve atingir chamados de concorrentes apenas porque atua na cidade.
4. Migrar frontend V19: `sbSaveMaterial`, `salvarMovimentacao`, `sbBaixaEstoque` e qualquer acesso direto a `chamado_materiais` para as novas RPCs; mostrar sucesso **somente após confirmação** e recarregar saldo do banco. Evitar seed automática por qualquer perfil.
5. Somente após o frontend passar nos testes: remover permissões DML diretas de `authenticated` e `anon` em `estoques`, `movimentacoes`, `chamado_materiais` e restringir políticas. **Confirmar que todas as chamadas legítimas usam RPC**, inclusive cadastro e cancelamento de materiais.
6. Aplicar constraints: `estoques(consorcio_id,material_id)` UNIQUE, consórcio não nulo, saldo >= 0; checar eventual regra `saldo <= contratado` versus reabastecimento antes de impor. Criar índice único somente após reaplicar auditoria e confirmar inexistência de duplicados.
7. Executar testes RBAC com os perfis de homologação e regressão V18 em ambiente isolado; só então planejar publicação/switch.

## Testes obrigatórios

- Empresa A não lê/escreve saldo ou item associado ao chamado atribuído à Empresa B, ainda que ambas atendam a mesma cidade.
- Empresa A pode consumir/editar/estornar **apenas** material de chamado atribuído a A; Master/Consórcio conforme regras acordadas.
- Usuário Prefeitura/Garantia não altera estoque sem autorização explícita.
- Saída acima do saldo falha sem alterar saldo, item ou movimentação.
- Concorrência de duas saídas para último saldo jamais resulta em saldo negativo nem em baixa dupla.
- Cada saída/entrada/estorno cria movimento consistente com saldo e `usuario_id`; qualquer erro reverte tudo.
- Cadastro de material novo informa `consorcio_id` pelo banco; registro reaparece depois de F5, sem sucesso falso.
- Alteração no catálogo não modifica saldo sem registrar o respectivo movimento.
- Material de teste eliminado não retorna após F5 nem por seed automática.

**Status:** especificação técnica salva; nenhuma correção de RLS/RPC aplicada ao Supabase. NÃO executar SQL de endurecimento isoladamente em produção.
