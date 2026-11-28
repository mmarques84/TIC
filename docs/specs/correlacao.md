# Spec de Telemetria na Central de alertas

**Status:** regra de abertura e gravidade pendentes de aprovação · **Atualizada em:** 2026-11-27

## O que faz

Liga os eventos de freada brusca da Autotrac à Central de alertas. A fila existente usa os registros de `derivado.evento` e `derivado.alerta`.

## Regras propostas

- **R1.** Processar somente os eventos `freada_brusca` gravados pela Telemetria. A condição para abrir o alerta e sua gravidade vêm de parâmetros aprovados pela TIC.
- **R2.** Preservar o identificador do veículo e o horário do evento. Usar o motorista vinculado na ingestão quando disponível. O alerta pode ser tratado com motorista pendente de identificação.
- **R3.** A mesma combinação de veículo, horário e tipo gera no máximo um evento derivado e um alerta. Reprocessar um lote preserva a tratativa existente.
- **R4.** A ativação começa nos eventos recebidos após a habilitação da regra. Uma carga do histórico exige uma decisão específica da TIC.
- **R5.** A fila continua aplicando as permissões e o escopo por operação da [Central](central-alertas.md).

## Como verificar

- [ ] Evento que atende à regra aparece na fila com placa, horário e gravidade previstos.
- [ ] Evento fora da regra permanece disponível em Condução.
- [ ] Reprocessar o lote não duplica a ocorrência nem reabre alerta tratado.
- [ ] Perfil sem acesso e usuário de outra operação não veem o alerta.
- [ ] A ativação não põe eventos antigos na fila.

## Em aberto

- [ ] Confirmar com Marcus, Michael ou Rafael se cada evento `freada_brusca` da Autotrac abre alerta ou se há um critério adicional. Confirmar a gravidade.

O roteiro V1 já registra parâmetros de redução de velocidade para caracterizar a freada. A spec de ingestão mantém em aberto a decisão de quais eventos recebidos da Autotrac devem abrir ocorrências na Central e com que gravidade.

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
