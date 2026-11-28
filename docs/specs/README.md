# Specs do TIC Painel Digital

Referência para a migração: [Fontes dos painéis atuais da TIC](fontes-paineis-atuais.md).

Uma spec por funcionalidade: **o que faz, regras, quem pode, como verificar, o que está em aberto.** Modelo: [`_modelo.md`](_modelo.md). Nenhuma funcionalidade é codada sem spec **aprovada**. Mudou a regra, muda a spec no mesmo commit. Lista e ordem justificadas em [`../plano.md`](../plano.md) §6.

| Spec | Marco | Status | Depende de |
|---|---|---|---|
| [seguranca-acesso.md](seguranca-acesso.md) | 1 | rascunho (login, me e logout implementados localmente) | — |
| [ingestao-autotrac.md](ingestao-autotrac.md) | 2 | implementada localmente (26/11): Telemetria e ATIC, testadas com o sandbox | estudo em `../estudo-api-atic.md`; mapa de eventos (Michael/Rafael) |
| ingestao-moovsec.md | 2 | a criar (estudo da API em `../estudo-api-moovsec.md`, 26/11) | URL do Moovsec da TIC, usuário de integração |
| [correlacao.md](correlacao.md) | 2–3a | proposta (28/11) para Michael e Rafael aprovarem os limites | Telemetria Autotrac |
| parametros.md | 2 | a criar | limites por operação (Michael) |
| [motor-jornada.md](motor-jornada.md) | 3a | implementada no banco (20/11) | skill regras-jornada; limites por operação (Michael) |
| alertas-escalonamento.md | 3a | a criar | teste de sirene |
| [central-alertas.md](central-alertas.md) | 2–3a | implementada com dados fictícios (20/11) | ingestão (dados reais); funciona com dados fictícios |
| triagem-ia.md | 3a | a criar | teto de custo (André) |
| opi.md | 3a | a criar | OPIs e vídeos (Natanael) |
| [jornada-painel.md](jornada-painel.md) | 3b | implementada com dados fictícios (23/11) | motor-jornada |
| torre.md | 3b | a criar | Datapar (Michael) |
| [cockpit-gerencial.md](cockpit-gerencial.md) | 3b | publicado com Telemetria Autotrac (27/11) | Telemetria Autotrac |
| cockpit-opi.md | 3b | a criar | opi |
| consumo-ia.md | 3b | a criar | orquestrador |
| [inicio-resumo.md](inicio-resumo.md) (Início com dados reais) | 2 | implementada (26/11) | alertas, jornada, integrações |
| [relatorio-conducao.md](relatorio-conducao.md) (Condução por motorista) | 3b | implementada (27/11 consulta; 28/11 ranking, detalhe e planilha) | ingestão Autotrac |
| [admin-usuarios.md](admin-usuarios.md) (Admin · Usuários e perfis) | 1–2 | implementada localmente (20/11) | seguranca-acesso |
| admin.md (parâmetros, integrações, auditoria) | 2–3b | a criar | seguranca-acesso |
