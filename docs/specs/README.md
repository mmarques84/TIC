# Specs do TIC Painel Digital

Uma spec por funcionalidade: **o que faz, regras, quem pode, como verificar, o que está em aberto.** Modelo: [`_modelo.md`](_modelo.md). Nenhuma funcionalidade é codada sem spec **aprovada**. Mudou a regra, muda a spec no mesmo commit. Lista e ordem justificadas em [`../plano.md`](../plano.md) §6.

| Spec | Marco | Status | Depende de |
|---|---|---|---|
| [seguranca-acesso.md](seguranca-acesso.md) | 1 | rascunho (login, me e logout implementados localmente) | — |
| ingestao-autotrac.md | 2 | a criar | documentação da API (Flávio) |
| ingestao-moovsec.md | 2 | a criar | export CSV + prova técnica |
| correlacao.md | 2 | a criar | ingestões |
| parametros.md | 2 | a criar | limites por operação (Michael) |
| [motor-jornada.md](motor-jornada.md) | 3a | implementada no banco (20/11) | skill regras-jornada; limites por operação (Michael) |
| alertas-escalonamento.md | 3a | a criar | teste de sirene |
| central-alertas.md | 3a | a criar | alertas, triagem |
| triagem-ia.md | 3a | a criar | teto de custo (André) |
| opi.md | 3a | a criar | OPIs e vídeos (Natanael) |
| jornada-painel.md | 3b | a criar | motor-jornada |
| torre.md | 3b | a criar | Datapar (Michael) |
| cockpit-gerencial.md | 3b | a criar | alertas, triagem |
| cockpit-opi.md | 3b | a criar | opi |
| consumo-ia.md | 3b | a criar | orquestrador |
| [admin-usuarios.md](admin-usuarios.md) (Admin · Usuários e perfis) | 1–2 | implementada localmente (20/11) | seguranca-acesso |
| admin.md (parâmetros, integrações, auditoria) | 2–3b | a criar | seguranca-acesso |
