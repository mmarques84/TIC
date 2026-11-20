---
name: regras-jornada
description: Regras de jornada de motorista do TIC (Lei 13.103/2015, CLT 235-C, CTB 67-C, decisões do STF), códigos de macro da Autotrac e do Datapar e os limites de cada operação. Consulte antes de escrever spec, SQL ou tela sobre jornada, interjornada, DSR, direção contínua, tempo de espera, parado 35 h, Torre de chegadas ou OPI item "respeitou a jornada".
---

# Regras de jornada (TIC)

Fonte: painéis do Rafael (`docs/estudo-paineis.md` §1 a §3) e roteiro (`docs/roteiro-fase1.md`). **Todo número abaixo é parâmetro** (`controle.parametro`, escopo por operação), nunca fixo no código. Onde as fontes divergem, a spec escolhe com o Michael; não decidir sozinho.

## Lei (vale para todas as operações)

| Tema | Regra |
|---|---|
| Jornada | 8 h normais + até 2 h extras (até 4 h por convenção coletiva) |
| Refeição | mínimo 1 h; até 2 h é descontada; o que passar volta a contar como tempo à disposição |
| Direção contínua | máximo 5h30 sem parar; 30 min de descanso a cada 6 h de direção |
| Interjornada | 11 h seguidas a cada 24 h; **sem fracionamento** (STF, ADI 5322, 2023) |
| DSR | 35 h (24 + 11) por semana; **sem acúmulo** em viagem longa (STF) |
| Tempo de espera | **conta como jornada** (STF); parado no cliente com jornada aberta pede tratativa |
| Semana | até 60 h (roteiro: de direção) |

## Limites por operação (o que cada painel usa hoje)

| Parâmetro | Jornada TIC (Autotrac) | Ipiranga (Datapar) | Torre | Roteiro |
|---|---|---|---|---|
| Atenção no dia | > 10 h trabalhadas | ≥ 9 h | — | — |
| Violação no dia | > 12 h ou aberta > 13 h | > 10 h | máx. 13 h | 8 + 2 |
| Semana | — | > 60 h (atenção ≥ 52 h) | — | 60 h |
| Dias sem DSR | alerta 6, vermelho 7 | — | — | alerta a partir do 7º |

## Detecções derivadas

- **Parado 35 h+:** posições no mesmo lugar (raio 1 km) por ≥ 35 h = DSR provável. Pede conferência se houve jornada aberta. **Não conta** se a telemetria mostra > 50 km do motorista logado no período.
- **Telemetria sem jornada:** > 20 km num dia sem jornada aberta → alerta. **Outro motorista logado** no veículo → alerta.
- **Contador de dias:** zera após 35 h parado; viagens longas podem ter exceção (a ajustar por tipo de viagem).
- **Cruzamentos (roteiro):** muita jornada e pouca direção = parado sem motivo; 14 h parado sem descarga programada = alerta.
- **Fadiga não dispara** com veículo parado, ignição desligada ou em descanso.

## Códigos de macro

**Datapar (Ipiranga):** 1 início de jornada · 2 início de refeição · 7 fim de refeição · 5 início de parada · 3 fim de jornada.
- Jornada líquida = fim − início − refeição − paradas; conta no dia em que começou.
- Sem "fim" há até 16 h = em curso; depois = "sem fim de jornada" (não soma horas).
- Mais de 18 h entre início e fim = inconsistente ("verificar"), não soma.

**Autotrac:** eventos vistos no painel: Parada para Refeição, Excesso da Jornada Estendida, entre outros. **Lista completa e códigos: aguardando a documentação da API (Flávio).** Não presumir.

## Status do motorista (painel Jornada TIC)

Dirigindo · Em jornada · Em serviço · Refeição · Parada/descanso · Fora de jornada · Sem eventos. Motorista "sem controle de jornada" na Autotrac: a Torre trata como descansado, saindo às 05h.

## Tratativas (o que a equipe registra)

DSR confirmado (descanso) · Tempo de espera (conta jornada) · Macro errada – corrigir · Jornada correta · Orientado / advertido · Outro. Com observação, quem e quando.
