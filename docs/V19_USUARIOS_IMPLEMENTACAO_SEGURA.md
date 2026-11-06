# V19 — Gestão real de usuários (trabalho em isolamento)

**Branch:** `fix/v19-usuarios-persistentes` (base: `desenvolvimento-v19`, commit `138e832b21393d7e41aa467b4a8e54d8f956f25a`).
**Estado:** especificação técnica inicial, **sem deploy, sem migration executada**.
**Ambiente alvo exclusivo:** Supabase V19 `xurrhczvyqpwyjemight`. Nunca aplicar à V18 `kvzcturkjibmsyjqafbt`.

## Evidência já validada no banco V19

- `public.usuarios`: `id uuid` (PK), `auth_user_id uuid` (nullable e UNIQUE), `consorcio_id`, `cidade_id`, `empresa_id`, `nome`, `email`, `telefone`, `cpf`, `cargo`, `perfil`, `vinculo_tipo`, `vinculo_id`, `org`, `status`, `ultimo_acesso`, `created_at`, `updated_at`.
- `authenticated` e `anon` não têm INSERT/UPDATE/DELETE direto em nenhuma das 14 tabelas operacionais.
- `usuarios` possui apenas política `SELECT`, e não há Edge Functions instaladas.
- O frontend `teste-v19/index.html` usa `carregarUsuariosDoBanco()` para leitura, mas `salvarUsuario()` edita apenas `DB.usuarios`. `saveUsers()` e `saveDB()` são no-ops; exibe vínculos antigos da V18 e opção Master indevida.

## Implementação proposta

1. **Serviço server-side isolado:** Supabase Edge Function `v19-usuarios` com autenticação por JWT de usuário via `auth.getUser(jwt)`, autorização por `public.usuarios` lido no servidor e chave administrativa exclusiva do runtime (nunca HTML ou GitHub). Sem autorização, rejeitar.
2. **Provisionamento:** enviar convite oficial Supabase Auth; vincular `auth.users.id` a `public.usuarios.auth_user_id` com validação transacional/compensação; não receber senha inicial nem expor a chave administrativa.
3. **Escopo:** Master administra todos; gestor de consórcio administra somente `prefeitura`, `empresa`, `garantia` do próprio consórcio. Nunca conceder Master/Consórcio fora do Master. Prefeitura, empresa e garantia não têm edição de usuários.
4. **Consistência:** prefeitura exige `cidade_id` ativa do consórcio; empresa exige `empresa_id` ativa do consórcio; garantia exige consórcio e nenhum vínculo de empresa; perfil Master não recebe consórcio. Confirmação do contrato de nomes e restrições no SQL43 antes de escrever migration.
5. **Alterações:** edição e desativação devem ser persistidas e auditadas no banco. Desativar nunca deve excluir registros operacionais; impedir autodesativação/acidente com último Master.
6. **Interface:** trocar modal legado por seleção dos dados reais de `consorcios`, `cidades`, `empresas`; esconder Master para consórcio; remover toasts de sucesso sem confirmação do servidor; substituir o `saveUsers()` no-op por operação autorizada.
7. **Evidência:** testes positivos e negativos de perfil/tenant, reload F5, conta criada no Auth + perfil associado, sessão do usuário desativado e inexistência de chave administrativa em HTML, logs ou repositório.

## Pendências antes de deploy

- Ler constraints/FKs/índices das tabelas `usuarios` e `auditoria` via SQL somente leitura.
- Definir e testar rollback de falhas entre Auth e Postgres (sistemas separados, transação distribuída inexistente).
- Validar convite/URL de redirecionamento permitida no Auth; verificar configuração de SMTP e templates.
- Verificar em ambiente de homologação a Edge Function e os testes negativos com perfis reais.
- Inspecionar e revisar patch; nenhum merge na `main` sem autorização.

## Implementação em andamento (06/11/2026)

- Código novo em `supabase/functions/v19-usuarios/index.ts` usando JWT de usuário, privilégio administrativo somente no servidor, convite oficial Supabase Auth e escopos tenant/perfil.
- Tela `teste-v19/v19-usuarios.js` substitui ações locais por chamadas autenticadas à Edge Function e consulta listas reais no Supabase.
- `teste-v19/index.html` inclui novo script apenas nesta branch; V18 e branch `main` não foram alteradas.
- Workflow `.github/workflows/v19-usuarios-validacao.yml` adicionado para validar sintaxe, **sem deploy**.

### Bloqueadores obrigatórios antes de implantar

1. **Atomicidade de auditoria:** a primeira implementação atualiza `usuarios` e insere em `auditoria` por chamadas distintas. Se a segunda falhar, a operação pode persistir sem log transacional. Migrar para operação SQL atômica (RPC server-only) e adicionar testes; não publicar a implementação atual.
2. **Testes da Edge Function:** validar tipagem com Deno e testes reais/negativos contra V19, incluindo escalonamento de perfis, seleção de empresa/cidade e concorrência.
3. **Provisionamento Auth:** configurar convite, SMTP e redirecionamento na V19; não testar no banco V18.
4. **Recuperação de falhas:** simular falha após convite/antes do vínculo sem apagar usuários Auth preexistentes e comprovar que não há conta ativa órfã.
5. **Revogação de sessão:** usuário inativo deve ser rejeitado por todas as RPCs e interfaces, mesmo com JWT previamente válido; dados já carregados não são apagados remotamente.
6. **Restrição de publicação:** GitHub branch e PR em rascunho não representam sistema homologado.

