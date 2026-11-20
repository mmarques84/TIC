# Spec: Admin · Usuários e perfis

**Status:** implementada localmente (20/11/2026; spec e layout aprovados pelo Marcus em 20/11) · **Marco:** 1–2 · **Atualizada em:** 2026-11-20
**Telas:** canvas "TIC Painel Digital · Login", artboards `AdminUsuarios`, `AdminNovo`, `AdminLink` (para validar) · **Tabelas:** `acesso.usuario`, `acesso.usuario_operacao`, `acesso.sessao`, `acesso.definicao_senha`, `cadastro.operacao`, `controle.auditoria` · **Workflows:** `api-admin` (novo), rotas de senha no `api-auth` · **Funções:** `sp_usuario_listar`, `sp_usuario_criar`, `sp_usuario_atualizar`, `sp_definicao_criar`, `sp_definicao_validar`, `sp_senha_definir`, `sp_sessao_listar`, `sp_sessao_revogar`, `sp_sessao_revogar_todas`
**Base:** [`seguranca-acesso.md`](seguranca-acesso.md) e a spec Admin · Usuários do Elysium (implementada em 19/11), adaptadas ao TIC.

## O que faz

Tela de quem administra o portal (perfil `admin`). Nela se cadastra cada pessoa da TIC que vai entrar (nome, e-mail, perfil e operações que vê), gera-se o link para ela criar a senha, muda-se o perfil, desativa-se quem saiu e encerram-se acessos abertos (ex.: a TV da central trocou de lugar). O admin vê só dados de cadastro e de acesso, não alertas nem imagens.

## Regras

**Quem usa**
- **R1.** Só quem tem a permissão `usuario.gerir` (hoje: perfil `admin`) abre a tela e usa as rotas `admin/*`. Os outros recebem 403 e não veem o item no menu.

**Lista**
- **R2.** Mostra todas as pessoas, ativas e inativas: nome, e-mail, perfil (por extenso), operações ("Todas" ou os nomes), situação ("Ativo"/"Inativo", sempre escrito), último acesso e senha ("Senha criada"/"Aguardando primeiro acesso").
- **R3.** Ordem: ativos primeiro, depois por nome. Busca por nome ou e-mail sem diferenciar maiúsculas e acentos. Filtro por perfil.

**Cadastrar e editar**
- **R4.** Cadastro pede nome, e-mail, perfil e operações; nasce **ativo** e **sem senha**.
- **R5.** E-mail guardado em minúsculas, sem espaços nas pontas; não repete ("Este e-mail já está cadastrado.").
- **R6.** Perfil vem da lista fechada (`acesso.perfil`); não se cria perfil por esta tela.
- **R7.** Operações: "Todas" ou uma ou mais operações cadastradas. Enquanto não houver operação cadastrada, só "Todas" aparece.
- **R8.** Editar muda nome, e-mail, perfil, operações e situação. Mudar o perfil, as operações ou desativar **encerra na hora todas as sessões** da pessoa; a tela avisa antes: "Isso encerra os acessos abertos de <nome>."
- **R9.** Não existe excluir: quem sai é **desativado**. Reativar é permitido.
- **R10.** (proposta) O admin não pode desativar a si mesmo nem tirar o perfil `admin` do **último admin ativo** ("O portal precisa de pelo menos um administrador ativo.").

**Link de senha**
- **R11.** O admin gera um link de criação de senha: uso único, vale 24 h. Se a pessoa já tem senha, o link é de troca.
- **R12.** O link aparece **uma única vez**, com "Copiar link" e a validade ("vale até 21/11 às 17:40"). Fechou, não volta: gera-se outro. Gerar um novo invalida os anteriores da mesma pessoa.
- **R13.** O admin nunca vê nem define a senha de ninguém. Pessoa inativa não recebe link ("Ative o usuário antes de gerar o link.").
- **R14.** Ao abrir o link, a pessoa cria a senha seguindo a política (seguranca-acesso R4) e já entra.

**Acessos**
- **R15.** Para cada pessoa: sessões abertas com navegador, IP, início e último uso. O admin encerra uma ou todas.

**Registro**
- **R16.** Auditoria com o admin como autor: `usuario.criar`, `usuario.editar` (antes e depois), `senha.link_criado`, `senha.definida`, `sessao.revogar`. Nunca grava o link nem o token.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Abrir, listar, cadastrar, editar | — | — | — | — | — | ✅ |
| Gerar link de senha | — | — | — | — | — | ✅ |
| Ver e encerrar sessões dos outros | — | — | — | — | — | ✅ |

## Fluxo

**Cadastrar alguém:** Usuários e perfis → "Novo usuário" → nome, e-mail, perfil, operações → Salvar → a tela oferece "Gerar link de senha" → link aparece uma vez → admin copia e manda à pessoa → ela abre `/definir-senha?token=…`, cria a senha e entra.

**Desativar:** lista → pessoa → "Desativar" → aviso → confirmar → sessões encerradas; o próximo pedido dela recebe 401.

Rotas (todas passam pelo `sub-autorizar` com `usuario.gerir`; escrita exige CSRF; id em `?id=` ou no corpo):

| Rota | Função |
|---|---|
| `GET admin/usuarios` | `sp_usuario_listar` |
| `POST admin/usuarios` | `sp_usuario_criar` |
| `PATCH admin/usuarios?id=` | `sp_usuario_atualizar` (campo ausente = não muda) |
| `POST admin/usuarios/link-senha` `{ id }` | `sp_definicao_criar` (o n8n gera o token e devolve o link uma vez) |
| `GET admin/sessoes?usuario=` | `sp_sessao_listar` |
| `DELETE admin/sessoes?id=` | `sp_sessao_revogar` |
| `POST admin/usuarios/encerrar-sessoes` `{ id }` | `sp_sessao_revogar_todas` |
| `POST auth/senha/link` `{ token }` (anônima) | `sp_definicao_validar` |
| `POST auth/senha/definir` `{ token, senha }` (anônima) | `sp_senha_definir` + `sp_sessao_criar` |

## Como verificar

- [x] **V1 (R1).** Perfil sem `usuario.gerir` em qualquer `admin/*` → 403; sem sessão → 401; menu sem o item.
- [x] **V2 (R2, R3).** Lista traz ativos e inativos, ativos primeiro; busca "joao" acha "João".
- [x] **V3 (R4, R5).** " Maria@Exemplo.com " grava `maria@exemplo.com`, ativo, sem senha; repetido → 409 "Este e-mail já está cadastrado."
- [x] **V4 (R6).** Perfil fora da lista → 400.
- [x] **V5 (R8).** Trocar perfil ou desativar: o cookie antigo da pessoa recebe 401 no pedido seguinte.
- [x] **V6 (R10).** Desativar a si mesmo ou rebaixar o último admin → 409.
- [x] **V7 (R11–R14).** Link abre `/definir-senha`, cria a senha e entra; a segunda vez o mesmo link é recusado; link novo invalida o anterior; link não aparece na auditoria.
- [x] **V8 (R13).** Link para inativo → 409 "Ative o usuário antes de gerar o link."
- [x] **V9 (R15).** Encerrar uma sessão: só aquele navegador recebe 401; "Encerrar todas": todos.
- [x] **V10 (R16).** Cada ação gera a linha certa em `controle.auditoria`, com o admin como autor.
- [ ] **V11 (manual).** Tela em 1366 e 1920 px; funciona em 390 px sem rolagem lateral. (Conferida só em 1440 px.)

## Fora do escopo

Cadastro de operações e bases (spec própria, ou junto com a lista oficial da TIC) · editar a matriz perfil × permissão pela tela · envio do link por e-mail · "Meus acessos" da própria pessoa · consulta da auditoria (tela própria).

## Em aberto

- [ ] Link entregue pelo admin (copiar e mandar) ou enviado por e-mail da TIC? (Michael / Flávio)
- [ ] Confirmar R10 (último admin e desativar a si mesmo). (Marcus)
- [ ] Lista oficial de pessoas, perfis e operações para o cadastro inicial. (TIC)

Conferido em 20/11/2026 (local): V1–V10 em `tests/sql/03_admin_usuarios.sql` (banco) e `tests/rotas/admin-usuarios.sh` (22 verificações nas rotas: 401/403, CSRF, e-mail normalizado, repetido 409, perfil inválido 400, link → criar senha → já entra, link usado de novo 400, troca de perfil derruba a sessão, inativo 409, desativar a si mesmo 409). Na tela a 1440 px: cadastrar → link aparece uma vez → abrir o link → criar senha → entra com o menu só do perfil Central. Lição: o nó Postgres do n8n não emite item quando a função não devolve linha; as listas devolvem uma linha com jsonb.
