# 002 · Arquitetura clean: domínio no banco e no front, n8n como adaptador

**Status:** aceita pelo Marcus · 20/11/2026

**Contexto.** O Marcus quer arquitetura clean no TIC. Com backend em n8n (decisão 001), não existe uma API em código onde montar entidades, casos de uso e repositórios no formato clássico. Escrever uma API em NestJS só para isso custaria horas que a Fase 1 (168 h) não tem.

**Decisão.** As camadas da clean architecture ficam distribuídas assim, com a regra de dependência sempre apontando para dentro (o domínio não conhece quem o chama):

| Camada clean | Onde fica no TIC | Regra |
|---|---|---|
| **Domínio** (entidades e regras) | Banco: tabelas com integridade (FK, `CHECK`, `NOT NULL`) + funções `fn_*` puras (ex.: `fn_jornada_liquida`, `fn_nivel_velocidade`) + tabela `controle.parametro` | Não sabe de HTTP, n8n nem tela. Testado em SQL. |
| **Casos de uso** | Funções `sp_*` (uma por ação: `sp_alerta_confirmar`, `sp_opi_validar`…) e rotinas de lote `job_*` (motor de regras, correlação) | Recebem `p_usuario_id`, conferem permissão, aplicam regra, gravam e auditam numa transação. |
| **Adaptadores de entrada** | n8n: webhooks `api-*` (autoriza → chama `sp_*` → responde) e ingestões `ing-*` (busca na fonte → grava no `bruto` → chama `job_*`) | Sem regra de negócio. Só traduz HTTP/fonte ↔ chamada de função. |
| **Adaptadores de saída** | n8n: `sub-autotrac-acao` (mensagem, sirene), `sub-claude` (IA com custo), envio de e-mail | Chamados por `sp_*`/`job_*` através de uma fila (`controle.fila_acao`), nunca direto do banco. |
| **Apresentação** | Angular, por feature: `dominio/` (tipos e regras de tela, sem Angular), `dados/` (serviços HTTP, mapeiam JSON → domínio), `estado/` (signals), `ui/` (componentes) | Componente nunca chama `HttpClient` direto; passa pelo serviço de `dados/`. |

**Front (Angular), estrutura por feature:**
```
src/app/
  core/            auth, api (interceptor, erros), layout, novidades
  ui/              design system (componentes genéricos tic-*)
  features/<tela>/
    dominio/       tipos, enums, funções puras (ex.: corDoNivel, formatarJornada) + testes
    dados/         <tela>.api.ts (HTTP) e mapeadores
    estado/        <tela>.store.ts (signals, ações)
    paginas/       componentes de rota
    componentes/   componentes da tela
```

**Alternativas.** API em NestJS com clean completa (mais código, foge do padrão e do prazo) · regra em nós Code do n8n (espalhada e sem teste).

**Consequências.**
- Toda regra de negócio tem teste em `tests/sql/` (domínio e casos de uso) e as regras de tela em `*.spec.ts` da pasta `dominio/`.
- Revisão rejeita: `INSERT/UPDATE` em nó do n8n, `if` de regra de negócio em nó Code, `HttpClient` em componente, limite numérico fixo em código (vai para `parametro`).
