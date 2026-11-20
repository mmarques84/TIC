# Plano da Fase 1: banco, agentes, skills e specs

**Status:** proposta do Marcus para validar com o Michael até o Marco 1 (27/11/2026). Base: `roteiro-fase1.md` e `estudo-paineis.md`.

## 1. Perguntas ao Michael antes do Marco 1

1. **Torre e Jornada Ipiranga dependem do Datapar**, que está na extensão a aprovar. Mas "jornada e torre migradas" é obrigatório. Sem Datapar, entra só a Jornada TIC (Autotrac); a Torre poderia rodar com previsão só pela Autotrac, sem agenda. Qual dos dois?
2. **Limites por operação:** Jornada TIC (10/12/13 h), Ipiranga (10 h/dia, 60 h/semana, 52 h atenção), Torre (13 h), roteiro (8 + 2). Confirmar que cada operação tem seus limites (proposta: `parametro` com escopo por operação).
3. **Tratativas de jornada** que hoje estão no artefato do Claude do Rafael: migrar ou começar do zero?
4. **pgvector:** nada nos painéis precisa. Proposta: PostgreSQL sim, pgvector só quando houver uso (ex.: achar alarmes parecidos).
5. **OPI:** confirmar FFRO 005 rev5 (sem item 36) e quais itens a IA consegue avaliar só por vídeo (1–4 e 32–37 parecem depender de outra fonte ou ficam N.A.).
6. **Resumo de violações por e-mail** (Natanael) continua existindo ou o cockpit substitui?
7. **Operações e bases:** lista oficial (Viagem, Entrega, Ipiranga, OPASC Itajaí/Biguaçu/Guaramirim, Araucária…) e quem vê qual.

## 2. Arquitetura

**Decidido em 20/11/2026:** PostgreSQL 17 + PostGIS (decisão 001) e arquitetura clean com domínio no banco e n8n como adaptador (decisão 002). A tabela abaixo é a proposta original, mantida como contexto.

| Camada | Proposta | Por quê |
|---|---|---|
| Banco | **PostgreSQL 16** (sem pgvector por enquanto) | Partição mensal nativa para 12 meses de eventos; o roteiro pede |
| Regras e escrita | **Funções SQL** (`sp_*`) com `p_usuario_id` e auditoria na mesma transação, como no Elysium | Regra num lugar só e testável |
| Motor de regras | Funções SQL de lote (jornada, DSR, velocidade, correlação), chamadas após cada ingestão | Regras de conjunto sobre eventos: SQL é o lugar natural |
| Ingestão e API | **n8n** (rotinas agendadas + webhooks `/api/...`), mesmo padrão do Elysium | Já dominado; ingestão a cada 60 s cabe |
| Front | Angular standalone + signals, responsivo (TV, computador, celular) | Mesmo padrão |
| IA | API do Claude na conta da TIC, sub-workflow único que registra custo | Teto mensal e roteamento Haiku → maior |
| Infra | VPS Hostinger em nome da TIC, Docker Compose, Caddy, backup diário fora da VPS | Mesmo padrão |

Pontos a provar na prova técnica (20/11 a 04/12): API Autotrac (incremental, mensagem, sirene); caminho do Moovsec (API Intelbras, servidor local com firewall ou e-mail `alertas@` + portal); desvio de relógio entre Autotrac e Moovsec; volume real (alarmes/dia × 12 meses).

## 3. Banco de dados (primeira versão)

Convenções: `snake_case`, PK `uuid` (v7), datas `timestamptz` em UTC, nada se apaga (soft delete), tabelas de evento particionadas por mês, `fonte_id` único por fonte para a ingestão ser idempotente.

### 3.1 Cadastro e acesso
| Tabela | Campos principais |
|---|---|
| `operacao` | código, nome, tipo (viagem, entrega), ativa |
| `base` | operação, nome, código Portran/Datapar, área (lat/long, raio) |
| `veiculo` | placa, tipo (cavalo, semi), frota, operação, serial do DVR, id Autotrac, id Moovsec, ativo |
| `conjunto` | cavalo, semi, início, fim (vem da "RELAÇÃO ATUALIZADA") |
| `motorista` | nome, matrícula, código Autotrac, operação, sem controle de jornada, foto de referência, status |
| `cliente` | nome, rede, endereço, lat/long, área cadastrada, observações (backlog entregas) |
| `usuario`, `perfil`, `permissao`, `sessao` | perfis diretoria, operação, frota/OPI, TI, central; permissões finas (ver imagem, validar OPI, aprovar parâmetro, acionar sirene) e escopo por operação |

### 3.2 Dados brutos (ingestão, particionados)
| Tabela | O que guarda |
|---|---|
| `ingestao_lote` | fonte, início, fim, cursor/último id, linhas, erro (o que já foi buscado não é buscado de novo) |
| `autotrac_posicao` | veículo, horário, lat/long, velocidade, ignição, limpador, odômetro, canal (celular/satélite) |
| `autotrac_evento` | veículo, horário, tipo (freada, força G, excesso, freio motor), valor |
| `autotrac_macro` | veículo, motorista, horário, macro (início/fim de jornada, refeição, parada…), local |
| `autotrac_login` | veículo, motorista, início, fim (→ `sessao_motorista`) |
| `autotrac_violacao` | as violações que a própria Autotrac já calcula (para comparar com as nossas) |
| `moovsec_alarme` | id Moovsec, veículo, horário UTC, tipo, canal, lat/long **corrigidos**, velocidade, link do clipe, status na origem, linha bruta |
| `datapar_*` | só se a extensão for aprovada (carga MF, agenda, macro lançamento) |

### 3.3 Derivados (motor de regras)
| Tabela | O que guarda |
|---|---|
| `sessao_motorista` | motorista, veículo, início, fim (quem dirigia a cada instante) |
| `jornada` | motorista, início, fim, amplitude, direção, refeição, descanso, trabalho, maior direção contínua, situação (ok, em curso, sem fim, inconsistente), fonte |
| `interjornada`, `parada` | horas; parada conta como DSR (com a regra dos 50 km) |
| `motorista_situacao` | retrato atual: status, parado desde, dias sem DSR, último DSR, alertas (o que a tela de jornada lê) |
| `evento` | o fato correlacionado: veículo, motorista, horário, tipo, origem (alarme, telemetria, regra), gravidade, regra disparada, ids de origem |
| `evento_frame` | 3 a 5 frames-chave por evento (arquivo na VPS ou link), câmera, instante |
| `alerta` | evento, nível, destino (painel, terminal, sirene, central), estado (aberto, em tratamento, confirmado, falso positivo, encerrado), quem tratou |
| `acao` | alerta, tipo (mensagem terminal, sirene, ligação), enviada em, resposta da Autotrac |
| `tratativa` | motorista ou alerta, tipo (DSR confirmado, tempo de espera, macro errada…), observação, quem, quando |

### 3.4 IA, OPI e controle
| Tabela | O que guarda |
|---|---|
| `triagem` | evento, resultado (verdadeiro, falso, inconclusivo), confiança, evidência (texto), modelo, prompt versão, custo, validado por, validação |
| `opi_modelo`, `opi_modelo_item` | formulário (FFRO 005 rev5), número, texto, seção, **polaridade**, só não anunciada, avaliável por vídeo |
| `opi` | motorista, veículo, mês, tipo (anunciada/não), trecho (início/fim), local, % calculado, infração, reincidência, ação sugerida, ação decidida, validação humana, PDF, link do vídeo |
| `opi_resposta` | opi, item, SIM/NÃO/N.A., origem (IA, humano), evidência, confiança |
| `parametro` | chave, valor, **escopo (global, operação, veículo)**, vigência início/fim, quem alterou, motivo |
| `consumo_ia` | agente, modelo, tokens entrada/saída/cache, custo, data, evento/opi |
| `credencial_status` | fonte, último sucesso, último erro, "senha mudou" (a credencial em si fica no cofre) |
| `auditoria` | quem, o quê, quando, antes/depois; inclui **visualização de imagem** (append-only) |

## 4. Agentes de IA

Captura e emissão de alertas **não são IA**: são rotinas de ingestão e o motor de regras. Na Fase 1 há **2 agentes** e um orquestrador de custo.

| Agente | Entra | Sai | Modelo |
|---|---|---|---|
| **Triagem de alarme** | tipo do alarme, 3–5 frames (câmera do alarme + outra câmera do mesmo instante), velocidade, contexto | verdadeiro / falso / inconclusivo, confiança (alta, média, baixa), evidência em texto | Haiku; reprocessa com modelo maior só se confiança baixa e gravidade alta |
| **OPI de condução** | trecho de 15 min (escolhido **por regra**: janela com mais alertas do motorista no mês), frames amostrados das 5 câmeras, telemetria do trecho (velocidade, freadas) | resposta por item avaliável com evidência e confiança, observação, ação sugerida; % e infração calculados pelo sistema | modelo maior (Sonnet), 1 por motorista/mês |
| **Orquestrador** (código, não IA) | pedido de análise | escolhe modelo, confere teto do mês, não reanalisa o que já tem resultado, grava `consumo_ia` | — |

Fase 2: agente de **entrega provável** (substitui a análise do Claude nos painéis de entrega) e resumo semanal em texto para a diretoria.

Prompts versionados em `prompts/`, avaliados contra a validação do Natanael na calibração (11 a 22/01).

## 5. Skills do projeto (Claude Code)

| Skill | Para quê |
|---|---|
| `pendencias` | Estado, o que falta, diário (criada) |
| `nova-funcionalidade` | Fluxo spec → layout → banco → n8n → front → testes → deploy (copiar e adaptar do Elysium) |
| `tela-tic` | Regras de tela: TV da central, computador, celular; tokens; prioridade com rótulo |
| `regras-jornada` | Lei 13.103, decisões do STF, códigos de macro, variações por operação; consulta obrigatória antes de mexer no motor de jornada |
| `integracao-autotrac` | Endpoints, autenticação, incremental, celular × satélite, mensagem e sirene (depois da documentação do Flávio) |
| `integracao-moovsec` | Parser do CSV (lat/long trocadas, milhar), caminho escolhido na prova técnica |

## 6. Specs (ordem dos marcos)

| Spec | Marco | Depende de |
|---|---|---|
| `seguranca-acesso.md` (login, perfis, escopo por operação, log de imagem) | 1 | — |
| `ingestao-autotrac.md` | 2 | documentação da API (Flávio, 25/11) |
| `ingestao-moovsec.md` | 2 | export CSV + caminho da prova técnica |
| `correlacao.md` (placa + horário, desvio de relógio, motorista logado) | 2 | as duas ingestões |
| `parametros.md` (tabela, escopo, vigência, quem aprova) | 2 | pergunta 2 |
| `motor-jornada.md` (jornada, interjornada, DSR, parado 35 h, telemetria) | 3a | `regras-jornada`, pergunta 2 |
| `alertas-escalonamento.md` (fadiga, velocidade, freada, obstrução; terminal, sirene, central) | 3a | ingestões; teste de sirene |
| `central-alertas.md` (fila, versão TV, confirmar / falso positivo / mensagem / sirene) | 3a | alertas, triagem |
| `triagem-ia.md` | 3a | frames; teto de custo (André, 27/11) |
| `opi.md` (seleção do trecho, agente, validação 50%, PDF FFRO 005, histórico) | 3a | OPIs e vídeos do SharePoint (Natanael, 27/11) |
| `jornada-painel.md` (migração da Jornada TIC + tratativas) | 3b | motor-jornada, pergunta 3 |
| `torre.md` (migração) | 3b | pergunta 1 |
| `cockpit-gerencial.md` (ranking, reincidência, tempo de resposta, falsos positivos evitados, Viagem × Entrega) | 3b | alertas, triagem |
| `cockpit-opi.md` | 3b | opi |
| `consumo-ia.md` | 3b | orquestrador |
| `admin.md` (usuários, perfis, parâmetros, status das credenciais) | 2–3b | seguranca-acesso |

## 7. Ainda falta receber

| Item | De quem | Prazo |
|---|---|---|
| Documentação e credenciais de teste da API Autotrac | Flávio | 25/11 |
| Resposta da Intelbras ou firewall do servidor Moovsec | Flávio | 25/11 |
| Export CSV do Moovsec (13/11) e export de alertas Autotrac do mesmo dia | Rafael | 25/11 |
| Parametrização de desvios e limites operacionais | pasta Midas | — |
| `validacao-alertas-tic.html` e vídeo de uso dos painéis | Rafael / André | 24/11 |
| OPIs preenchidas e vídeos de 15 min (SharePoint) | Natanael | 27/11 |
| Teto mensal de IA | André | 27/11 |
