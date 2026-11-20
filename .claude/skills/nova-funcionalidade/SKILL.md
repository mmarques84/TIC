---
name: nova-funcionalidade
description: Fluxo padrão do TIC Painel Digital para criar ou mudar uma funcionalidade, da spec ao deploy (spec → layout → banco → n8n → front → testes → revisão → deploy). Use quando o usuário pedir uma funcionalidade nova, uma mudança de regra, "vamos fazer a central de alertas", "implementa a spec X", ou quando for escrever uma spec em docs/specs/.
---

# Nova funcionalidade no TIC Painel Digital

Arquitetura: `docs/decisoes/001-stack.md` e `002-arquitetura-clean.md`. Checklist técnico: skill `tela-tic`. Regras de jornada: skill `regras-jornada`.

## 1. Spec primeiro

1. Procure a spec em `docs/specs/` (índice em `docs/specs/README.md`).
2. Não existe? Copie `docs/specs/_modelo.md` para `docs/specs/<nome>.md` e preencha a partir do que já está decidido: `docs/roteiro-fase1.md`, `docs/estudo-paineis.md` (os painéis do Rafael e do Natanael **são a especificação funcional**), `docs/plano.md`, `docs/decisoes/`.
3. Regras numeradas (R1, R2…), curtas e testáveis. Cada regra tem pelo menos um item em "Como verificar". Todo limite numérico vira linha de `controle.parametro`, com escopo (global ou operação).
4. **Não invente regra de negócio.** O que não está decidido vai para "Em aberto", com dono (Michael, André, Rafael, Natanael, Flávio).
5. Atualize o índice. Mostre a spec ao Marcus e **pare** até ele aprovar.

## 2. Layout

Tela nova ou mudada: protótipo para validar, nos tamanhos que a tela usa (TV da central 1920 px, computador 1366 px, celular 390 px), com os estados da spec (carregando, vazio, erro, sem permissão). Dados fictícios. Pare para aprovação.

## 3 a 5. Construir (de dentro para fora)

1. **Domínio:** migration aditiva em `db/migrations/` + funções puras `fn_*` em `db/funcoes/`, com teste em `tests/sql/`.
2. **Casos de uso:** `sp_*` (ação do usuário, com `p_usuario_id` e auditoria) ou `job_*` (lote do motor de regras), com teste.
3. **Adaptadores:** workflow n8n `api-<tela>` (primeiro nó `sub-autorizar`) ou `ing-<fonte>`; código dos nós em `n8n/codigo/`; exportar para `n8n/workflows/`.
4. **Front:** `features/<tela>/` com `dominio/`, `dados/`, `estado/`, `paginas/`, `componentes/`.

Ramo `feat/<nome>`, commits `tipo(escopo): o que mudou`.

## 6. Testes

Cada item de "Como verificar" vira teste ou fica marcado **manual** com o resultado anotado. Sempre: sem sessão → 401, perfil sem permissão → 403, operação de outro escopo → não aparece, escrita → linha em `controle.auditoria`, ver imagem → linha em `controle.auditoria`.

## 7. Revisão

`/code-review` no ramo; ler o diff contra a spec. Rejeitar: regra em nó do n8n, `INSERT/UPDATE` fora de `sp_*`, `HttpClient` em componente, limite fixo no código, dado real em teste.

## 8. Fechar

- Spec "implementada"; diário da skill `pendencias` atualizado; commit.
- Deploy só com o Marcus: backup → migrador → workflows → front → conferir na VPS.
