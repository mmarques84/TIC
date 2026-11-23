# Spec: Central de alertas

**Status:** implementada localmente com dados fictícios (20/11/2026; spec e layout aprovados pelo Marcus em 20/11) · **Marco:** 2–3a · **Atualizada em:** 2026-11-20
**Telas:** canvas "TIC Painel Digital · Login", artboards `CentralAlertas` (computador) e `CentralTV` (TV da central), para validar · **Tabelas:** `derivado.alerta`, `derivado.evento`, `derivado.evento_frame`, `derivado.acao`, `ia.triagem`, `controle.fila_acao`, `controle.auditoria` · **Workflows:** `api-central` (novo), `sub-autotrac-acao` (saída, junto com a ingestão) · **Funções:** `sp_central_listar`, `sp_central_resumo`, `sp_alerta_detalhe`, `sp_alerta_pegar`, `sp_alerta_confirmar`, `sp_alerta_falso`, `sp_alerta_mensagem`, `sp_alerta_sirene`
**Base:** roteiro §4, §8, §13 e critérios de aceite 1–3; `estudo-paineis.md`; spec `seguranca-acesso.md` (permissões e auditoria de imagem).

## O que faz

É onde o operador da central e a equipe tratam os alertas que precisam de ação: alarmes de câmera (fadiga, celular, sem cinto…) e de telemetria (freada brusca, velocidade), já correlacionados com o motorista logado e com a foto do mesmo instante, e com a pré-triagem da IA. Em vez de abrir e-mail ou o portal do Moovsec, a pessoa vê a fila, abre o alerta, olha as fotos e decide: confirmar, marcar falso positivo, mandar mensagem para o terminal do caminhão ou acionar a sirene. Na TV da central, a mesma fila aparece em letra grande, sem botões, para todo mundo acompanhar.

## Regras

**Quem usa**
- **R1.** Ver a fila exige `alerta.ver`; confirmar, marcar falso e assumir exigem `alerta.tratar`; mensagem e sirene exigem `alerta.acionar`; ver as fotos exige `imagem.ver`. Hoje: central e operação fazem tudo; frota/OPI trata mas não aciona; diretoria só vê.
- **R2.** Cada pessoa vê só os alertas das operações dela (escopo do usuário, seguranca-acesso R11).

**Fila**
- **R3.** A fila mostra os alertas **abertos** e **em tratamento**. Ordem: nível (crítico, grave, médio, leve) e, dentro do nível, o mais recente primeiro.
- **R4.** Cada linha mostra: nível com **rótulo escrito** além da cor, tipo ("Fadiga: 11 bocejos em 1 h"), placa do cavalo, motorista (ou "ninguém logado"), hora do evento e "há X min", local (texto da Autotrac quando houver; senão a cidade mais próxima ou as coordenadas), miniatura da primeira foto, resultado da IA ("IA: verdadeiro · alta") e quem está tratando.
- **R5.** Filtros: nível, tipo, operação, busca por placa ou motorista, e a aba "Tratados hoje" (confirmados, falsos e encerrados do dia).
- **R6.** A fila se atualiza a cada 5 s. Alerta **crítico novo** fica destacado e, se o operador ligar o som, toca um aviso.
- **R7.** No topo, contadores por nível dos alertas abertos e o tempo do alerta aberto mais antigo.

**Detalhe e fotos**
- **R8.** Abrir um alerta mostra: as 3 a 5 fotos do instante (câmera de fadiga, frontal, laterais, interna), velocidade e limpador no momento, a evidência da IA, as ações já feitas (mensagem, sirene, quem e quando) e os outros alertas do mesmo motorista nas últimas 24 h.
- **R9.** Cada abertura das fotos grava `imagem.ver` na auditoria com quem viu, qual alerta e quando (LGPD). As fotos só são servidas a quem tem `imagem.ver`, nunca por link público.
- **R10.** O vídeo não fica no portal: o detalhe traz o link do clipe no Moovsec quando houver.

**Tratar**
- **R11.** **Assumir**: o alerta passa a "em tratamento por <nome>". Outro operador vê isso e pode assumir também (assumir de novo troca o responsável e fica na auditoria), para não travar a fila se alguém sair.
- **R12.** **Confirmar** (é real): estado "confirmado", com observação opcional. Se a IA disse "falso", conta como discordância para a calibração.
- **R13.** **Falso positivo**: estado "falso positivo", com motivo de uma lista curta (mão no rosto, objeto confundido, imagem ruim, câmera desalinhada, outro) e observação opcional. Se a IA disse "verdadeiro", conta como discordância.
- **R14.** Confirmar ou marcar falso tira o alerta da fila (vai para "Tratados hoje"). Não existe apagar alerta.

**Agir na cabine**
- **R15.** **Mensagem ao terminal**: texto pronto por tipo de alerta, que o operador pode editar (até 200 caracteres). Ela vai para a fila de saída e o n8n manda para a Autotrac. A tela mostra o estado: pendente, enviada, confirmada pelo terminal ou erro.
- **R16.** **Sirene**: pede confirmação ("Acionar a sirene do TST1A01?") e segue o mesmo caminho da mensagem.
- **R17.** O escalonamento automático de fadiga (spec `alertas-escalonamento.md`) também gera ações; elas aparecem no alerta como "automática".
- **R18.** Mensagem e sirene não fecham o alerta: depois de agir, o operador ainda confirma ou marca falso.

**TV da central**
- **R19.** Rota própria `/alertas/tv`, para o perfil com `alerta.ver`. Mostra só a fila aberta e os contadores, com letra grande, sem botões, sem fotos de pessoas (só placa, tipo, nível, motorista, local e há quanto tempo), relógio e a hora da última atualização. Atualiza a cada 5 s.
- **R20.** Se a TV ficar mais de 1 min sem conseguir atualizar, mostra um aviso grande "Sem atualização desde HH:MM".

**Registro**
- **R21.** Toda ação grava `controle.auditoria`: `alerta.assumir`, `alerta.confirmar`, `alerta.falso`, `alerta.mensagem`, `alerta.sirene`, `imagem.ver`.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver a fila e a TV | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Ver as fotos | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Assumir, confirmar, falso positivo | — | ✅ | ✅ | ✅ | — | ✅ |
| Mensagem ao terminal e sirene | — | ✅ | — | ✅ | — | ✅ |

## Fluxo

1. A ingestão e a correlação criam `derivado.evento` com as fotos; a regra (ou o escalonamento) abre o `derivado.alerta`; a IA grava a `ia.triagem`.
2. A tela consulta `GET /api/central/alertas` a cada 5 s.
3. O operador abre um alerta (`GET /api/central/alerta?id=`, que audita `imagem.ver`), assume, olha as fotos e age.
4. Mensagem e sirene: `sp_alerta_mensagem`/`sp_alerta_sirene` gravam `derivado.acao` e `controle.fila_acao`; o workflow de saída envia à Autotrac e atualiza o estado da ação.
5. Confirmar ou falso: `sp_alerta_confirmar`/`sp_alerta_falso`, que também registram a validação da triagem.

| Rota | Função |
|---|---|
| `GET central/alertas?aba=&nivel=&tipo=&q=` | `sp_central_listar` |
| `GET central/resumo` | `sp_central_resumo` (contadores; usada também pela TV) |
| `GET central/alerta?id=` | `sp_alerta_detalhe` (audita `imagem.ver`) |
| `GET central/foto?id=` | serve a foto (n8n lê do volume de fotos depois de autorizar) |
| `POST central/alerta/assumir` `{ id }` | `sp_alerta_pegar` |
| `POST central/alerta/confirmar` `{ id, observacao }` | `sp_alerta_confirmar` |
| `POST central/alerta/falso` `{ id, motivo, observacao }` | `sp_alerta_falso` |
| `POST central/alerta/mensagem` `{ id, texto }` | `sp_alerta_mensagem` |
| `POST central/alerta/sirene` `{ id }` | `sp_alerta_sirene` |

## Como verificar

- [x] **V1 (R1).** Diretoria: vê a fila, os botões de tratar não aparecem e as rotas de escrita dão 403. TI: 403 na fila.
- [x] **V2 (R3, R4).** Com alertas fictícios de vários níveis, a fila sai em crítico → leve e, no mesmo nível, do mais novo para o mais velho; cada linha tem rótulo escrito do nível.
- [x] **V3 (R5).** Filtro por nível e busca por placa funcionam; "Tratados hoje" traz só os do dia.
- [x] **V4 (R8, R9).** Abrir o detalhe gera uma linha `imagem.ver` na auditoria com o usuário e o alerta; sem `imagem.ver`, as fotos não vêm.
- [x] **V5 (R11).** Assumir mostra "em tratamento por <nome>" para outro usuário; assumir de novo troca o responsável.
- [x] **V6 (R12, R13, R14).** Confirmar e marcar falso tiram o alerta da fila; falso sem motivo é recusado; a discordância com a IA fica registrada na triagem.
- [x] **V7 (R15, R16, R18).** Mensagem e sirene criam ação "pendente" e item em `controle.fila_acao`; o alerta continua aberto.
- [ ] **V8 (R19, R20).** `/alertas/tv` não mostra botões nem fotos; sem API por mais de 1 min mostra o aviso de "sem atualização".
- [x] **V9 (R21).** Cada ação gera a linha certa na auditoria.
- [ ] **V10 (manual).** Computador a 1366 e 1920 px; TV a 1920×1080 legível a 3 m.

## Fora do escopo

Ingestão e correlação (specs próprias) · escalonamento automático de fadiga (`alertas-escalonamento.md`) · o agente de triagem (`triagem-ia.md`) · envio real à Autotrac (entra com a prova técnica; até lá a ação fica "pendente") · mapa · vídeo dentro do portal.

## Em aberto

- [ ] Textos prontos das mensagens ao terminal por tipo de alerta (o terminal tem limite de caracteres?). (Flávio / TIC)
- [ ] A sirene precisa de dupla confirmação ou de um perfil específico? (Michael)
- [ ] Lista de motivos de falso positivo: está boa? (Natanael)
- [ ] Local: a Autotrac entrega o texto ("em POSTO X - CIDADE")? Senão, usamos a cidade mais próxima. (Flávio)
- [ ] A TV fica logada com um usuário próprio do perfil central (sessão longa)? Ligado à pergunta 6 do Marco 1. (Michael)

Conferido em 20/11/2026 (local, dados fictícios de `tests/dados/central-ficticio.sql`): V1–V7 e V9 em `tests/sql/05_central_alertas.sql` (5/5 conjuntos ok); rotas `api-central` por curl (fila na ordem, resumo, detalhe com 5 fotos e texto padrão, motivo obrigatório 400, sem sessão 401); na tela a 1440 px: assumir, falso positivo com motivo (alerta sai da fila e abre o próximo); TV a 1920×1080. **Pendente:** as fotos ainda são quadros de exemplo (a rota `central/foto` entra com a ingestão do Moovsec e o volume de fotos); envio real de mensagem e sirene (fila de saída fica "pendente" até a prova técnica da Autotrac); V8 sem API por 1 min e V10 legibilidade a 3 m (manual).
