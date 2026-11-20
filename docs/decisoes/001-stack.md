# 001 · PostgreSQL + funções SQL + n8n + Angular

**Status:** aceita pelo Marcus · 20/11/2026 (levar ao Michael no Marco 1, 27/11)

**Contexto.** O TIC é um projeto de **eventos com tempo e posição**: ~290 mil posições/dia (200 caminhões a cada 60 s), ~6.500 alarmes de câmera/dia, macros, jornada, correlação "quem dirigia às 06:10", raio de 1 km para descanso, 12 meses de retenção. O roteiro do Michael sugere PostgreSQL + pgvector. O Elysium usa MySQL 8.4. O Marcus usa SQL Server nos projetos grandes.

**Decisão.**
- **PostgreSQL 17** (imagem `postgis/postgis`), com **PostGIS** para distância e áreas. **pgvector fica de fora** até haver uso concreto.
- **Schemas por camada:** `cadastro`, `bruto`, `derivado`, `ia`, `acesso`, `controle` (auditoria, parâmetros, consumo).
- Tabelas de evento **particionadas por mês** (`bruto.autotrac_posicao`, `bruto.autotrac_evento`, `bruto.moovsec_alarme`, `derivado.evento`), **com chave estrangeira** para o cadastro. Partições com mais de 12 meses são desanexadas e removidas por rotina.
- Datas em `timestamptz` (UTC); períodos em `tstzrange` quando ajuda (sessão do motorista, jornada).
- Regras e escrita em **funções `sp_*`** (PL/pgSQL), como a decisão 002 do Elysium: recebem `p_usuario_id`, validam, gravam e auditam na mesma transação; erro de regra com `RAISE EXCEPTION` e código em maiúsculas. Detalhe da arquitetura em clean: decisão 002.
- **n8n** para ingestão agendada, webhooks `/api/...` e chamadas à IA. **Angular** standalone + signals, responsivo. **Caddy** com HTTPS. Tudo em Docker Compose numa VPS Hostinger.

**Alternativas.**
- **MySQL 8.4** (igual ao Elysium, código reaproveitável): tabela particionada não aceita chave estrangeira; contas de tempo e espaço mais pobres; não tem schemas.
- **SQL Server** (o que o Marcus mais usa): o Express limita o banco a 10 GB e 1,4 GB de RAM, o que não cabe em 12 meses de posições; o Standard exige licença paga pela TIC, fora do orçamento.
- **TimescaleDB:** bom para série temporal, mas é mais uma peça; partição nativa basta.

**Consequências.**
- As funções de login, sessão, usuários e auditoria do Elysium são **reescritas** em PL/pgSQL (mesmo desenho). Estimativa: 2 a 3 dias a mais no começo.
- O n8n conecta com usuário que só tem `EXECUTE` nas `sp_*` (sem acesso direto às tabelas).
- A prova técnica mede a ingestão de 60 s no n8n; se não aguentar, a ingestão sai para um worker e esta decisão é revista.
