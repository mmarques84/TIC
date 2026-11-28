# Spec: Correlação · eventos da Autotrac viram alertas na Central

**Status:** proposta (28/11/2026) para o Marcus levar ao Michael e ao Rafael; nada é ativado sem a aprovação dos limites · **Marco:** 2–3a · **Atualizada em:** 2026-11-28
**Telas:** nenhuma nova (os alertas aparecem na Central de alertas, spec `central-alertas.md`) · **Tabelas:** lê `bruto.autotrac_evento`, `controle.parametro`; grava `derivado.evento`, `derivado.alerta`, `controle.auditoria` · **Workflows:** a correlação roda no fim de cada ciclo do `ing-autotrac-telemetria` · **Funções:** `job_correlacao_telemetria`
**Base:** roteiro v1 §9 (alertas da Fase 1: fadiga, velocidade, freada brusca, câmera obstruída; faixas de velocidade seca e molhada), parâmetros já cadastrados (`velocidade.seca`, `velocidade.molhada`, `freada.*`), dados reais da VPS (26–28/11).

## O que faz

Decide quais eventos de telemetria que a Autotrac manda (≈ 30 mil por dia) viram **alerta na Central** e com que **gravidade**. A grande maioria não vira alerta: fica para o relatório de Condução e para o Cockpit. Vira alerta só o que o roteiro manda tratar na hora (freada brusca e excesso de velocidade), com limites em parâmetros que a TIC aprova e ajusta sem mexer no código. Ocorrências repetidas do mesmo caminhão em poucos minutos viram **um** alerta, para a Central não afogar.

## Volume real (VPS, 24 h entre 26 e 27/11/2026)

| Tipo recebido | Por dia | Caminhões | Observação |
|---|---:|---:|---|
| Pressão do óleo baixa | 1.172 | 81 | ruído alto; manutenção, não central |
| Velocidade excessiva | 274 | 65 | só **4** com velocidade ≥ 81 km/h (campo a confirmar, ver Validação) |
| Velocidade excessiva na chuva | 2 | 2 | |
| Freada brusca | 1 | 1 | |
| Aceleração brusca | 1 | 1 | |
| Fora da faixa verde, marcha lenta, RPM, banguela | ≈ 6.000 | — | condução/economia, não central |

Com a proposta abaixo, a Central receberia **algo como 5 a 10 alertas de telemetria por dia**.

## Regras (proposta)

**O que abre alerta**
- **R1.** Abre alerta, por tipo, conforme `controle.parametro` `correlacao.regras` (editável por quem tem `parametro.editar`). Proposta inicial:

  | Tipo | Abre alerta? | Nível (proposta) |
  |---|---|---|
  | `freada_brusca` | sim | **grave** |
  | `velocidade_excessiva` | sim, se a velocidade atinge a faixa de pista seca | pelas faixas: 81–83 leve, 84–86 médio, > 86 grave |
  | `velocidade_excessiva_chuva` | sim, se atinge a faixa de pista molhada | 60–63 leve, 64–66 médio, > 66 grave |
  | `aceleracao_brusca` | não (vai para Condução) | — |
  | RPM, fora da faixa verde, marcha lenta, banguela | não (Condução) | — |
  | pressão do óleo baixa/alta | não (visão por caminhão; alerta de manutenção é outra spec) | — |
  | eventos de câmera da Autotrac (ADAS/SDS) | não, até mapear os nomes reais | — |
  | `desconhecido`, temporizado, ignição | nunca | — |

- **R2.** A velocidade comparada com as faixas é a do campo que a Autotrac confirmar (hoje a ingestão grava `VelocityMax`, que parece não ser a velocidade do excesso: ver Validação). **Enquanto não confirmar, excesso de velocidade não abre alerta**; freada brusca abre.
- **R3.** Só evento com o caminhão em movimento: freada a partir de `freada.velocidade_min` (10 km/h) quando o evento traz a velocidade inicial.

**Juntar repetições**
- **R4.** Mesmo caminhão + mesmo tipo dentro de `correlacao.janela_min` (proposta: 10 min) = **um** alerta. O título conta as ocorrências ("3 freadas bruscas em 10 min") e o nível sobe para o maior entre elas.
- **R5.** A partir de `correlacao.repeticoes_para_subir` ocorrências na janela (proposta: 3), o nível sobe um degrau (leve → médio → grave → crítico).

**Quem, onde, quando**
- **R6.** O alerta guarda o veículo, o horário do primeiro evento e o motorista da ingestão (código da Autotrac; sem cadastro = "motorista não identificado"). Local: coordenadas do evento até a ATIC trazer o texto do local.
- **R7.** Um evento bruto gera no máximo um evento derivado (chave: veículo + horário + tipo). Reprocessar não duplica nem reabre alerta já tratado (spec atual R3).
- **R8.** Só os eventos recebidos **depois** de ligar a correlação (`correlacao.ativa` = true e `correlacao.desde`). Carregar o histórico é decisão à parte (spec atual R4).
- **R9.** Permissões e escopo por operação são os da Central (spec atual R5).

**Mais tarde (fora desta entrega)**
- **R10.** Marco 2: quando o Moovsec estiver ligado, freada da Autotrac e alarme de câmera do mesmo caminhão a até `correlacao.camera_s` segundos (proposta: 5) viram **o mesmo** evento, com as fotos (roteiro: "freada brusca da Autotrac aparece com a imagem da câmera do mesmo instante").

## Quem pode

Como a Central (`central-alertas.md`). Mudar os limites da correlação exige `parametro.editar` (admin; hoje nenhum outro perfil).

## Fluxo

1. Fim do ciclo do `ing-autotrac-telemetria` → `job_correlacao_telemetria(lote)`.
2. Para os eventos do lote que abrem alerta (R1–R3), cria ou soma o evento derivado e o alerta (R4–R7).
3. A Central já mostra (fila, nível escrito, tratativa, auditoria).

## Como verificar

- [ ] **V1 (R1).** Freada brusca abre alerta grave; RPM, faixa verde, óleo e desconhecido não abrem.
- [ ] **V2 (R1, R2).** Com a velocidade confirmada: 82 km/h em seca = leve, 85 = médio, 90 = grave; 65 em molhada = médio. Sem confirmar (parâmetro desligado): excesso não abre.
- [ ] **V3 (R4, R5).** 3 freadas do mesmo caminhão em 10 min = 1 alerta "3 freadas bruscas em 10 min", nível subiu um degrau; a 4ª em 30 min abre outro.
- [ ] **V4 (R7).** Reprocessar o lote não duplica e não reabre alerta tratado.
- [ ] **V5 (R8).** Ligar a correlação não põe eventos antigos na fila.
- [ ] **V6 (R9).** Perfil sem `alerta.ver` e pessoa de outra operação não veem.
- [ ] **V7 (manual).** Na VPS, em 1 dia ligado: a quantidade de alertas fica na faixa estimada (5–10/dia) e a TIC acha útil.

## Fora do escopo

Fadiga e câmera (Moovsec: spec `ingestao-moovsec.md` e escalonamento de fadiga) · alerta de manutenção por pressão do óleo · mensagem e sirene automáticas (dependem da prova técnica da Autotrac) · triagem por IA dos alertas de telemetria.

## Em aberto (perguntas para o Michael e o Rafael)

- [ ] **Freada brusca:** todo evento de freada da Autotrac abre alerta? Nível **grave** está bom? (o roteiro define a freada — queda ≥ 15 km/h em 1 s a partir de 10 km/h —, mas não o nível)
- [ ] **Velocidade:** qual campo da Autotrac é a velocidade do excesso? (ver Validação abaixo) Até responder, excesso não abre alerta.
- [ ] **Repetições:** juntar em 10 min e subir o nível a partir de 3 está bom?
- [ ] **Pressão do óleo:** 1.172 por dia em 81 caminhões parece sensor ruidoso. A manutenção quer um alerta próprio (outra spec) ou só o relatório por caminhão?
- [ ] **Força G > 0,5** (roteiro): a Autotrac manda isso em algum evento? Não apareceu nos dados.

## Validação de velocidade em produção (27/11/2026)

O roteiro técnico (p. 6, §9) define as faixas por pista seca e molhada. As faixas já estão cadastradas em `velocidade.seca` e `velocidade.molhada` e são consultadas por `controle.fn_nivel_velocidade`.

Simulação em leitura sobre a coluna `velocidade`, que a ingestão preenche priorizando `VelocityMax`:

| Tipo recebido | Registros | Abaixo do limiar inicial | Leves | Médios | Graves |
|---|---:|---:|---:|---:|---:|
| Excesso de velocidade (16) | 478 | 473 | 5 | 0 | 0 |
| Excesso de velocidade na chuva (18) | 11 | 0 | 9 | 2 | 0 |

No tipo 16, `VelocityMax` variou de 11 a 81, com média de 29,6. Em 46 registros (43 do tipo 16 e 3 do tipo 18), `VelocityEnd` superou `VelocityMax`.

**Pendência para ativação:** confirmar com a Autotrac a unidade e qual campo representa a velocidade a comparar com os limites da TIC. Conciliar o evento bruto e a ocorrência exibida no portal Autotrac para o mesmo veículo e horário antes de habilitar a geração de alertas. A simulação não gravou eventos derivados nem alertas.

**Cruzamento com as APIs disponíveis:** em uma segunda consulta, o banco tinha 494 eventos de velocidade, zero posições ATIC, zero veículos vinculados à ATIC e zero eventos de câmera da Autotrac com velocidade no payload ingerido. Nenhum dos 494 eventos pôde ser pareado com uma leitura de câmera do mesmo veículo em até cinco segundos. Consultar novamente `alltelemetryevents` reproduz a fonte original. A comparação pode ser feita com um relatório do Telemetria Business ou, após habilitação da ATIC, com `positions` e o horário efetivo da medição. Uma posição próxima pode corroborar a leitura, mas pode não capturar o pico.

O Documento de Apoio da API ATIC V14.4, entregue pela TIC, documenta a rota de posições por veículo (§ veículos, p. 30). Testamos `GET /v1/accounts` a partir da VPS de integração com a credencial disponível e recebemos HTTP 401. Confirmar a chave, a permissão ATIC do usuário e a liberação do IP de saída com a Autotrac. O manual ATIC descreve a velocidade da posição. A interpretação de `VelocityMax` e `VelocityEnd` dos eventos depende da documentação específica de Telemetria ou da conciliação com o relatório.
