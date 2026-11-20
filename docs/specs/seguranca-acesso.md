# Spec: Segurança e acesso (login, sessão, perfis)

**Status:** rascunho (implementado localmente para teste; aguarda aprovação do Marcus e do Michael) · **Marco:** 1 · **Atualizada em:** 2026-11-20
**Telas:** canvas "TIC Painel Digital · Login" (login, erro, esqueci, definir senha, início) · **Tabelas:** `acesso.*`, `controle.auditoria`, `controle.parametro` · **Workflows:** `sub-autorizar`, `api-auth` · **Funções:** `acesso.sp_login_buscar`, `sp_login_falha`, `sp_sessao_criar`, `sp_autorizar`, `sp_auth_me`, `sp_logout`

Base: spec de segurança e login do Elysium (já aprovada), adaptada ao TIC (PostgreSQL, perfis por função e escopo por operação).

## O que faz

A equipe da TIC entra no portal com e-mail e senha. Cada pessoa tem um perfil (diretoria, operação, frota/OPI, central, TI, admin) que define o que vê no menu e o que pode fazer, e pode ficar restrita a algumas operações. Toda entrada, saída, falha e bloqueio fica na auditoria.

## Regras

- **R1.** Login por e-mail (comparado em minúsculas, sem espaços) e senha. Não há cadastro aberto: só o admin cria usuários.
- **R2.** A senha nunca é guardada nem trafega para o banco em claro: o n8n calcula PBKDF2-SHA512 (210 mil iterações, sal de 16 bytes) e o banco guarda só o hash.
- **R3.** Senha errada, e-mail inexistente, usuário inativo ou bloqueado recebem a **mesma** resposta ("E-mail ou senha incorretos", HTTP 401) e o mesmo tempo de resposta (o n8n confere um hash fictício quando o e-mail não existe).
- **R4.** Política de senha nova: no mínimo 12 caracteres, não pode ser comum nem conter o e-mail ou o nome.
- **R5.** Depois de `acesso.tentativas_max` (5) erros seguidos, o usuário fica bloqueado por `acesso.bloqueio` (15 min). Login certo zera o contador.
- **R6.** A sessão é um token aleatório de 32 bytes num cookie `HttpOnly`, `SameSite=Lax`, `Secure` em produção (`__Host-tic`; em desenvolvimento `tic-dev`). O banco guarda só o SHA-256 do token.
- **R7.** Toda rota que muda algo (POST, PATCH, DELETE) exige o cabeçalho `X-XSRF-TOKEN` igual ao cookie `XSRF-TOKEN` da sessão (o banco compara os hashes). Sem isso: 403 `CSRF`.
- **R8.** A sessão cai depois de `acesso.sessao_inatividade` (12 h) sem uso ou `acesso.sessao_maxima` (7 dias) no total, o que vier antes. Logout derruba na hora.
- **R9.** Todo webhook com sessão começa por `sub-autorizar` → `acesso.sp_autorizar(token, csrf, método, permissão)`. Exceções: health e login (anônimas).
- **R10.** O que cada perfil pode: tabela `acesso.perfil_permissao` (carga inicial em `007_carga_inicial.sql`). Admin tem todas. O menu do front esconde o que o perfil não pode, mas quem bloqueia é o banco (403 `SEM_PERMISSAO`).
- **R11.** Escopo por operação: `todas_operacoes = true` vê tudo; senão, só as operações de `acesso.usuario_operacao`. (Aplicado nas leituras de cada tela.)
- **R12.** Auditoria (só inclusão) de: login, falha de login, bloqueio, logout, criação e edição de usuário e **cada imagem de câmera aberta**.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| entrar, ver o próprio perfil, sair | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| criar e editar usuários e perfis | — | — | — | — | — | ✅ |
| alterar parâmetros | — | — | — | — | — | ✅ |

## Fluxo

1. `POST /api/auth/login` → `sp_login_buscar` → n8n confere o hash → certo: `sp_sessao_criar` + `sp_auth_me` e devolve os dois cookies; errado: `sp_login_falha` e 401.
2. `GET /api/auth/me` → `sub-autorizar` → `sp_auth_me` (nome, perfil, permissões, operações).
3. `POST /api/auth/logout` (com CSRF) → `sub-autorizar` → `sp_logout` e apaga os cookies.
4. O Caddy converte `X-Tic-Cookie-1/2` em dois `Set-Cookie` (o n8n só manda um cabeçalho de cada nome).

## Como verificar

- [x] **V1 (R3).** E-mail inexistente e senha errada → 401 `CREDENCIAIS_INVALIDAS` (curl e tela).
- [x] **V2 (R5).** 5 falhas → bloqueado; login certo bloqueado não cria sessão (`tests/sql/02_acesso.sql`).
- [x] **V3 (R6, R8).** Login certo → cookies `tic-dev` (HttpOnly) e `XSRF-TOKEN`; `me` responde; depois do logout `me` → 401.
- [x] **V4 (R7).** Logout sem `X-XSRF-TOKEN` → 403 `CSRF`; com → 200.
- [x] **V5 (R10).** Perfil sem permissão → `sp_autorizar` = proibido; tela mostra "Sem acesso".
- [x] **V6 (R12).** Login, falha, bloqueio e logout geram linha em `controle.auditoria`.
- [ ] **V7 (R4).** Definir senha pelo link (rotas `/senha/esqueci`, `/senha/link`, `/senha/definir` ainda não publicadas).
- [ ] **V8 (R11).** Escopo por operação nas leituras (entra com as telas de dados).
- [ ] **V9 (manual).** Em HTTPS na VPS: cookie `__Host-tic` com `Secure`.

## Fora do escopo

Login com Google ou Microsoft; segundo fator; cadastro aberto; acesso dos motoristas.

## Em aberto

- [ ] Tempo de inatividade (12 h) e duração máxima (7 dias) estão bons para a central, que fica logada na TV? (Michael)
- [ ] Como o link de "esqueci a senha" chega à pessoa: e-mail da TIC ou só o admin gera? (Michael / Flávio)
- [ ] Lista oficial de usuários com perfil e operação. (TIC)
- [ ] O que a diretoria e a TI podem ver em detalhe (imagens? jornada?). (Michael / André)
