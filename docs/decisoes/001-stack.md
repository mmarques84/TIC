# 001 · PostgreSQL + funções SQL + n8n + Angular

**Status:** proposta · 20/11/2026 · Marcus (validar com o Michael no Marco 1, 27/11)

**Contexto.** O roteiro sugere "mesmo padrão do Elysium" com PostgreSQL + pgvector e eventos particionados por mês, retenção de 12 meses. Volume esperado: ~6.500 alarmes de câmera por dia, posição de 200 caminhões a cada 60 s (~290 mil linhas/dia), macros e eventos de telemetria. As regras (jornada, DSR, velocidade, correlação) são de conjunto sobre eventos. O Elysium usa MySQL + procedures + n8n + Angular.

**Decisão (proposta).**
- **PostgreSQL 16**, partição mensal nativa em `autotrac_posicao`, `autotrac_evento`, `moovsec_alarme`, `evento`; descarte de partições após 12 meses (depois de exportar, se a TIC quiser).
- **pgvector fica de fora** até haver um uso concreto.
- Regras e escrita em **funções SQL** (`sp_*`) que recebem `p_usuario_id` e gravam `auditoria` na mesma transação, como a decisão 002 do Elysium. Motor de regras em funções de lote chamadas depois de cada ingestão.
- **n8n** para ingestão agendada, webhooks `/api/...` e chamadas à IA (sub-workflow único que registra custo).
- **Angular** standalone + signals, responsivo (TV, computador, celular).
- VPS Hostinger em nome da TIC, Docker Compose, Caddy, backup diário fora da VPS.

**Alternativas.** MySQL (igual ao Elysium; partição menos prática e sem vantagem aqui) · workers em Node/Python no lugar do n8n para a ingestão de 60 s (mais controle; avaliar se o n8n aguentar mal na prova técnica) · TimescaleDB (bom para série temporal, mas mais uma peça).

**Consequências.**
- Procedures do Elysium não se copiam direto: mudam de MySQL para PL/pgSQL (padrão igual, sintaxe diferente).
- A prova técnica precisa medir a ingestão a cada 60 s no n8n; se não aguentar, a ingestão sai para um worker e esta decisão é revista.
