# Estudo: API ATIC da Autotrac

**Fonte:** "Documento de Apoio – API ATIC – V14.4" (Autotrac, confidencial: o PDF fica em `material-cliente/autotrac/`, fora do git) e o sandbox público da Autotrac. **Lido em:** 25/11/2026. Base da spec `ingestao-autotrac.md` (a criar).

## Como funciona

- **Endereços:** produção `https://aapi3.autotrac-online.com.br/aticapi` · sandbox (dados fictícios, aceita qualquer usuário) `https://wapi.autotrac-online.com.br/sandboxaticapi`. Swagger do sandbox: `/sandboxaticapi/docs/v1`.
- **Autenticação:** cabeçalho `Ocp-Apim-Subscription-Key` (chave gerada no Home Office da Autotrac) + `Authorization: Basic usuário:senha` **em texto puro, sem base64** (o Basic padrão dá 400 em produção; conferido 25/11) de um usuário do Supervisor Web com a permissão **"Acesso à ATIC API"**. TLS 1.2+.
- **Só responde do IP de saída cadastrado** no formulário do Home Office (senão 401/403). Produção não abre no navegador (404).
- **Unidades autorizadas:** só veículos na lista de unidades autorizadas devolvem dados, e só a partir do momento em que entraram nela. **A Autotrac cobra por veículo na lista.**
- **Respeita o "conjunto de controle"** do usuário no Supervisor: veículo fora do conjunto do usuário da API não aparece.
- **Guarda 7 dias.** Cada chamada aceita no máximo **72 h** de janela (422 se passar). Sem datas, devolve só as últimas 12 h: sempre mandar `_dateTimeFrom`/`_dateTimeTo` em UTC (`2026-11-25T10:00:00+00:00`).
- **Paginação:** resposta `{ Data: [...], Limit, Offset, IsLastPage }`; parâmetros `_limit` e `_offset` (até 500 por página nos exemplos). `_last=true` traz só o último registro.
- **Erros:** 400 formato, 401 chave/usuário/IP, 403 sem permissão/IP/URL errada, 404 rota, 422 regra (janela > 72 h, veículo inválido ou fora das unidades autorizadas).

## O que usamos e onde cai

| Recurso (GET) | Por veículo? | Para quê | Tabela |
|---|---|---|---|
| `/v1/accounts` | não | contas (satélite e celular) | — (parâmetro) |
| `/v1/accounts/{conta}/vehicles` | não | frota: código interno, nº do equipamento, placa | `cadastro.veiculo.id_autotrac` |
| `/v1/accounts/{conta}/authorizedvehicles` | não | quem está na lista (e é cobrado) | conferência |
| `/v1/drivers` | não | motoristas: código e CPF | `cadastro.motorista.codigo_autotrac` |
| `/v1/driverstatus` | não | excesso de jornada **calculado pela Autotrac** | comparar com nosso motor |
| `.../vehicles/{v}/positions` | sim | posição, velocidade, ignição, hodômetro (**÷ 100**), canal | `bruto.autotrac_posicao` |
| `.../vehicles/{v}/returnmessages` | sim | **macros** (`MacroNumber` 1–63 satélite, 1–100 celular, `MacroVersion`) e texto livre (0) | `bruto.autotrac_macro` |
| `.../vehicles/{v}/driverlogs` | sim | login/logout do motorista no veículo (`LogoutTime` 1970 = sem logout) | `autotrac_login` |
| `.../vehicles/{v}/expandedalerts` | sim | alertas de OBC: RPM, velocidade, temperaturas e entradas/saídas por ID | `bruto.autotrac_evento` |
| `/v1/informationregionslog` | não | entrada/saída de áreas cadastradas no Supervisor | Torre de chegadas (talvez) |

Pontos para o desenho da ingestão:
- A macro **não traz o motorista**: o motorista sai do login/logout daquele veículo na hora da macro (`driverlogs`).
- Quatro chamadas **por veículo** a cada ciclo: com a frota inteira o volume é alto (ex.: 400 veículos × 4 = 1.600 chamadas por ciclo). Precisamos saber o limite de chamadas.
- Não existe recurso de "freada brusca / força G / excesso" com esse nome: o que há são os **alertas expandidos de OBC**, cujos IDs de entrada/saída só fazem sentido com o "Dicionário_Alerta_Expandido" (pedir ao consultor).
- `DirectionGPS` com valor fora de N/S/L/O é erro de GPS (descartar).
- A API devolve **CPF**: guardar só o necessário para o de-para do motorista (LGPD), nunca mostrar na tela.

## O que a API **não** faz (impacta o Marco 1)

- **Não envia mensagem nem aciona sirene.** Só lê as mensagens enviadas (`forwardmessages`). O Marco 1 do roteiro prevê "mensagem e sirene em veículo de teste": perguntar à Autotrac se existe outro recurso (ou outra API) para isso.

## O que os painéis do Rafael consultam hoje (25/11/2026)

Nenhum dos 4 HTML chama API: os dados vêm **embutidos no arquivo** (um "retrato" gerado por uma rotina do Rafael, de hora em hora das 04h às 22h nas entregas), e os ajustes manuais ficam em planilhas no OneDrive dele (`observacoes_entregas.xlsx`, `ATENDIMENTO ARAUCARIA.xlsx`). O que cada painel usa e de qual recurso viria na API:

| Painel | O que ele usa | Recurso da Autotrac (ou outra fonte) |
|---|---|---|
| **Jornada TIC** ("Autotrac Jornada Business + Telemetria") | sequência de macros de jornada com hora e posição | ATIC `returnmessages` (macro + lat/long) |
| | parado no mesmo lugar (raio 1 km) por 35 h+ | ATIC `positions` / posição das macros |
| | km por motorista e por dia, login do motorista ("Telemetria Business") | Telemetria `alltelemetryevents` (hodômetro, `DriverID`, `DriverName`) + ATIC `driverlogs` |
| **Entregas Araucária** e **Entregas OPASC** | posição e referência do cavalo ("Em MATRIZ TIC…, 0,0 km/h") | ATIC `positions` (`Landmark`, `Velocity`) |
| | passou pela área de informação do cliente (entrada e saída) | ATIC `informationregionslog` |
| | saída da base da Ipiranga Araucária (início da previsão de chegada) | ATIC `informationregionslog` ou `positions` |
| | pedidos, cliente, litros, programação | **Portran** (sistema da Ipiranga; transportador 1305) — não é Autotrac |
| | aviso de chegada do motorista | grupo de WhatsApp (manual) |
| | endereço do cliente para a previsão | OpenStreetMap |
| **Jornada Ipiranga** | macro de lançamento, até 10 h/dia e 60 h/semana | **Datapar** — não é Autotrac |

### Como o painel de Jornada do Rafael é alimentado (dados do HTML de 16/11, só estrutura)

- O HTML traz um JSON compactado (gzip) com `meta.fonteTelemetria = "Jornada Business + Telemetria Business"`, **158 motoristas** e **período de 14 dias** (02/11 a 16/11). A API ATIC só guarda 7 dias: ou a rotina dele acumula histórico, ou os dados vêm de **relatórios dos portais Jornada Business e Telemetria Business** da Autotrac (exportação). Confirmar com o Rafael.
- Cada motorista tem o `code` da Autotrac, a sequência de eventos e as **violações já calculadas pela Autotrac** (`violacoesAutotrac`: parada de descanso curta, refeição excedida, direção > 5h30, jornada normal e estendida excedidas).
- Cada evento vem com o **nome da macro** e o **tipo de evento do Jornada Business** (número). Isso é a base do `controle.macro_mapa`:

| Macro (nome na TIC) | Evento do Jornada Business (nº) |
|---|---|
| INICIO DE JORNADA | Início de Jornada (1) |
| FIM DE JORNADA | Fim de Jornada (2) |
| REINICIO · INICIO DE VIAGEM · INICIO DE VIAGEM - DESLOCAMENTO VAZIO | Início de Direção (3) |
| CHEGADA NO CLIENTE - CARGA · CHEGADA NO CLIENTE - DESCARGA · Parada Pesagem - Balança | Fim de Direção (4) |
| PARADA PARA REFEICAO | Parada para Refeição (5) |
| PARADA EM VIAGEM | Parada para Descanso (6) |
| FIM DE VIAGEM | (aparece com violação 13) |

  Eventos de alerta gerados pelo próprio Jornada Business: 12 tentativa de início de jornada não permitida · 13 violação de jornada · 22 intervalo de repouso diário não cumprido · 24 tempo mínimo de refeição não cumprido · 25 tempo mínimo de descanso não cumprido · 33 risco de excesso de dias consecutivos · 34 excesso de dias consecutivos.
- Telemetria por motorista: km nas últimas 48 h, km na semana, km parado, login atual e "outro login".

Consequências:
- A **Torre de chegadas / entregas** precisa da API **ATIC** (posições e áreas de informação), não só da de Telemetria. E as **áreas de informação dos clientes** precisam estar cadastradas no Supervisor.
- A **Jornada** precisa das duas: macros e login pela ATIC, km por motorista pela Telemetria.
- Perguntar ao Rafael **como a rotina dele busca os dados** (API com qual usuário? exportação do Supervisor?): se ele já usa a API ATIC, o acesso já existe.

## Perguntas (levar na conversa de hoje)

1. Qual **IP de saída** foi cadastrado no Home Office? Precisa ser o da VPS (187.53.119.147); para testar antes da VPS, cadastrar também o IP do escritório do dev.
2. O usuário da API vê **todos os veículos** (conjunto de controle)? Quantos veículos estão na **lista de unidades autorizadas** e quanto custa cada um?
3. Qual o **limite de chamadas** (por minuto/dia)? Com 4 chamadas por veículo por ciclo, qual intervalo é aceitável (5 min? 15 min?)?
4. Tabela de **macros da TIC** no Supervisor (número, versão e nome: início de jornada, refeição, descanso, fim…), para preencher `controle.macro_mapa`.
5. O documento **"Dicionário_Alerta_Expandido"** (IDs de entrada/saída dos alertas de OBC).
6. Existe recurso para **enviar mensagem e acionar sirene**? Se não, como fazer a prova técnica do Marco 1?
7. Os veículos estão com **"OBC ativo"** (necessário para os alertas expandidos)?

## Teste de conexão

`scripts/testar-atic.mjs` (Node 18+): sem variáveis testa o sandbox; com `ATIC_URL`, `ATIC_CHAVE`, `ATIC_USUARIO` e `ATIC_SENHA` no ambiente testa a produção. Só faz GET e mostra status, quantidades e nomes de campo (nada de nome, CPF ou placa). Sandbox conferido em 25/11/2026: os 9 recursos responderam 200.
