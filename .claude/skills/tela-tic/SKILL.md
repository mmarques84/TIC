---
name: tela-tic
description: Como criar ou alterar tela, componente, workflow do n8n ou SQL do TIC Painel Digital seguindo a arquitetura clean (domínio no banco, n8n como adaptador, Angular em camadas), PostgreSQL, sessão/perfis, auditoria e responsividade (TV, computador, celular). Use ao construir Central de alertas, Jornada, Torre, OPI, Cockpits, Admin, componentes em frontend/src/app/ui, workflows em n8n/ ou SQL em db/.
---

# Criar tela ou funcionalidade no TIC

Leia antes: `docs/decisoes/002-arquitetura-clean.md`, `docs/montagem.md`, a spec da funcionalidade.

## Banco (PostgreSQL)

1. Estrutura nova = `db/migrations/NNN_descricao.sql`, **só aditiva**. Tabela no schema certo (`acesso`, `cadastro`, `bruto`, `derivado`, `ia`, `controle`).
2. Integridade no banco: FK `ON DELETE RESTRICT`, `NOT NULL` por padrão, `CHECK` em todo valor fechado, `UNIQUE` na chave natural (ex.: `id_moovsec`). Nada se apaga: `ativo = false`.
3. Datas `timestamptz` em UTC; "do dia" calculado em `America/Sao_Paulo`. Períodos com `tstzrange` quando houver sobreposição a testar.
4. Tabela de evento grande: particionada por mês (`PARTITION BY RANGE (horario)`), com a partição do mês seguinte criada por `job_particoes`.
5. Ingestão idempotente: `INSERT ... ON CONFLICT (chave_da_fonte) DO NOTHING`; cursor em `bruto.ingestao_lote`.
6. **Domínio** = `fn_*` (`IMMUTABLE`/`STABLE`, sem escrita). **Caso de uso** = `sp_*(p_usuario_id, ...)`: confere permissão e escopo, valida, grava, chama `int_auditar`, tudo numa transação. Erro de regra: `RAISE EXCEPTION 'CODIGO_EM_MAIUSCULAS' USING ERRCODE = 'P0001'`.
7. Limite numérico **nunca** fixo: `fn_parametro('chave', operacao_id)`.
8. Leitura também por `sp_*`, já filtrando pelo escopo de operação do usuário.

## n8n (adaptador, sem regra)

1. `api-<tela>`: webhook `api/...` → **`sub-autorizar`** (exceções: login, health, definição de senha) → `SELECT sp_...` → responde. Nenhum `if` de regra de negócio.
2. `ing-<fonte>`: agenda → busca incremental na fonte → grava em `bruto` via função de ingestão → chama `job_*`. Falha de credencial atualiza `controle.credencial_status`.
3. Saídas (mensagem ao terminal, sirene, IA) só por `sub-*`, lendo `controle.fila_acao`. IA só por `sub-claude`, que grava `ia.consumo` e respeita o teto.
4. Conferir erro do banco em todo nó (`erroDoBanco()`); erro de regra vira 4xx com o código.
5. Nunca logar imagem, nome de motorista ou credencial: só ids.

## Front (Angular, clean por feature)

```
features/<tela>/dominio/      tipos e funções puras (sem Angular) + *.spec.ts
features/<tela>/dados/        <tela>.api.ts (HttpClient) e mapeadores JSON → domínio
features/<tela>/estado/       <tela>.store.ts (signals)
features/<tela>/paginas/      componentes de rota (lazy)
features/<tela>/componentes/  componentes da tela
```
- Componente nunca usa `HttpClient`; chama a store, que chama `dados/`.
- Componente genérico vai para `ui/` com prefixo `tic-`. Cores só por tokens `var(--tic-*)`. Nível/gravidade sempre com **rótulo escrito** além da cor.
- Paleta e fonte oficiais da TIC (Roteiro V2, 24/11/2026), em `frontend/src/styles/tokens.css`: **marinho** `--tic-marinho` (#1F2F58) em menu, títulos e dados principais; **azul** `--tic-azul` (#337AB7) em links, IA e séries secundárias; **amarelo** `--tic-amarelo` (#F5B201) só em filtros, botões e atenção, sempre com texto em marinho. Fonte **Titillium Web** 400/600/700 (Tahoma de reserva), servida pelo portal. Ordem do menu: Central de alertas, Cockpit gerencial, Cockpit OPI, Jornada, Torre de chegadas, Consumo de IA, Admin.
- Esconder o que o perfil não pode (via `/api/auth/me`); o backend continua bloqueando.
- Estados: carregando, vazio, erro, sem permissão. Textos em português com o vocabulário da TIC.

## Responsivo

- **TV da central (1920 px):** Central de alertas e Torre em modo quadro: fonte grande, sem hover, atualização automática, contraste alto.
- **Computador (1366 px):** tabelas com filtro, ordenação e linha expansível (padrão dos painéis do Rafael).
- **Celular (390 px):** tabelas viram cards; ações principais com alvo ≥ 44 px; sem rolagem horizontal.
- Testar em 390, 768, 1366 e 1920 px.

## Conferência final

Sem sessão → 401 · perfil sem permissão → 403 · outra operação → vazio · caminho feliz → 200 + `controle.auditoria` · tela nos 4 tamanhos. Dizer o que não foi verificado.
