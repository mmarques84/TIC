# Spec: Motor de jornada

**Status:** implementada no banco (20/11/2026; aprovada pelo Marcus em 20/11) · **Marco:** 3a (adiantado) · **Atualizada em:** 2026-11-20
**Telas:** nenhuma (a tela é a spec `jornada-painel.md`) · **Tabelas:** lê `bruto.autotrac_macro`, `bruto.autotrac_posicao`, `bruto.autotrac_login`, `derivado.sessao_motorista`; grava `derivado.jornada`, `derivado.parada`, `derivado.motorista_situacao`, `derivado.evento`, `controle.macro_mapa` (nova) · **Funções:** `job_jornada`, `fn_direcao`, `fn_km`, `fn_km_motorista`, `fn_limite_min` (domínio), `int_jornada_motorista`, `int_gravar_jornada`, `sp_macro_mapa_*` (admin)
**Base:** skill `regras-jornada`, `estudo-paineis.md` §1 e §2 (painéis do Rafael), roteiro §10.

## O que faz

Rotina sem IA que transforma as macros que o motorista aperta no terminal (início de jornada, refeição, parada, fim) e as posições do caminhão em **jornadas calculadas**: horas trabalhadas, direção, refeição, descanso, interjornada, dias sem descanso semanal (DSR) e paradas longas. Com isso marca o que está **dentro**, em **atenção** ou em **violação** da Lei 13.103, por motorista, e deixa um retrato atual de cada um ("dirigindo há 4h10", "7 dias sem DSR"). É o que alimenta a tela de Jornada, a Torre (previsão de chegada), a OPI (item 35, "respeitou a jornada?") e a Central (não alertar fadiga de quem está em descanso).

## Regras

**Entrada e mapa de macros**
- **R1.** Cada código de macro de cada fonte é traduzido por uma tabela editável `controle.macro_mapa` (fonte, número → significado): `inicio_jornada`, `fim_jornada`, `inicio_refeicao`, `fim_refeicao`, `inicio_parada`, `fim_parada`, `inicio_espera`, `fim_espera`, `ignorar`. Nada de código de macro fixo no cálculo.
- **R2.** Carga inicial do mapa só com o que é conhecido: Datapar 1 início de jornada, 2 início de refeição, 7 fim de refeição, 5 início de parada, 3 fim de jornada. Os códigos da Autotrac entram quando chegar a documentação; macro sem mapa é contada e aparece como "macro desconhecida" (não some, não quebra o cálculo).
- **R3.** O cálculo é refeito para uma janela (padrão: os últimos 8 dias) a cada ingestão de macros, e é idempotente: rodar duas vezes dá o mesmo resultado. Macro que chega atrasada (satélite) entra no recálculo seguinte.

**Jornada**
- **R4.** Jornada = de `inicio_jornada` até `fim_jornada` do mesmo motorista. Conta no dia (São Paulo) em que começou.
- **R5.** Tempo líquido de trabalho = amplitude − refeição − paradas de descanso. Tempo de espera (macro de espera, ou parado no cliente com jornada aberta) **conta como jornada** (STF).
- **R6.** Refeição: o que passar de `jornada.refeicao_max` (2 h) volta a contar como tempo à disposição; refeição abaixo de `jornada.refeicao_min` (1 h) é violação.
- **R7.** Direção = minutos em que o veículo da sessão do motorista estava em movimento (velocidade > 0 nas posições), dentro da jornada. Direção contínua = maior trecho de direção sem pausa ≥ `jornada.pausa_direcao` (30 min).
- **R8.** Jornada sem `fim_jornada`: até `jornada.em_curso_max` (16 h) desde o início é **em curso**; depois vira **sem fim** (não soma horas e pede tratativa "macro errada").
- **R9.** Jornada com mais de `jornada.inconsistente` (18 h) entre início e fim é **inconsistente** (não soma; pede tratativa).

**Limites (todos em `controle.parametro`, com escopo por operação)**
- **R10.** Situação da jornada do dia: **atenção** acima de `jornada.atencao_dia`; **violação** acima de `jornada.limite_dia` ou com jornada aberta há mais de `jornada.aberta_max`.
- **R11.** Semana (segunda a domingo): **atenção** a partir de `jornada.atencao_semana`; **violação** acima de `jornada.limite_semana`.
- **R12.** Direção contínua acima de `jornada.direcao_continua_max` (5h30) = violação.
- **R13.** Interjornada (do fim de uma jornada ao início da próxima) abaixo de `jornada.interjornada_min` (11 h, sem fracionamento) = violação.
- **R14.** Valores iniciais propostos (a confirmar com o Michael, pergunta 2 do Marco 1):

| Parâmetro | Global (Jornada TIC) | Ipiranga |
|---|---|---|
| `jornada.atencao_dia` | 10 h | 9 h |
| `jornada.limite_dia` | 12 h | 10 h |
| `jornada.aberta_max` | 13 h | 13 h |
| `jornada.atencao_semana` | — | 52 h |
| `jornada.limite_semana` | 60 h | 60 h |
| `jornada.dias_sem_dsr.atencao` | 6 | 6 |
| `jornada.dias_sem_dsr.alerta` (já existe) | 7 | 7 |

**Descanso semanal e paradas**
- **R15.** Parada longa = posições do veículo dentro de `parada.raio` (1 km) por 11 h ou mais. Parada de 35 h ou mais **conta como DSR**, exceto se o motorista logado rodou mais de `parada.km_invalida_dsr` (50 km) no período.
- **R16.** Dias sem DSR = dias com início de jornada desde o último DSR. Atenção em `jornada.dias_sem_dsr.atencao` (6), violação em `jornada.dias_sem_dsr.alerta` (7).
- **R17.** Parada de 35 h+ com jornada aberta no período fica como **conferir** (pode ser DSR com macro errada ou tempo de espera).

**Telemetria cruzada**
- **R18.** Motorista que rodou mais de `telemetria.km_sem_jornada` (20 km) num dia sem jornada aberta → **conferir**.
- **R19.** Outro motorista logado no veículo enquanto a jornada deste está aberta → **conferir**.
- **R20.** Parado mais de `jornada.parado_sem_descarga` (14 h) com jornada aberta e sem descarga programada → **atenção**. (A "descarga programada" depende do Datapar; sem ele, a regra marca só "parado com jornada aberta".)

**Saída**
- **R21.** `derivado.motorista_situacao` guarda o retrato atual: status (dirigindo, em jornada, refeição, parada/descanso, fora de jornada, sem eventos), veículo, parado desde, último DSR, dias sem DSR e a lista de alertas (código, nível atenção/violação/conferir, texto).
- **R22.** Cada violação nova vira um `derivado.evento` (origem `regra`, tipo `jornada_*`, gravidade conforme o parâmetro), uma vez só por ocorrência (sem repetir a cada recálculo).
- **R23.** Motorista com `sem_controle_jornada` não entra no cálculo (aparece como "sem controle").
- **R24.** Tratativa registrada (DSR confirmado, tempo de espera, macro errada…) não apaga o cálculo: fica ao lado e tira a pendência "conferir" da tela.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| (rotina) recalcular | — | — | — | — | — | sistema |
| Editar o mapa de macros | — | — | — | — | — | ✅ |
| Ver o resultado | (spec jornada-painel) | | | | | |

## Fluxo

1. A ingestão grava macros, posições e logins em `bruto.*`.
2. O n8n chama `job_jornada(desde)`; o job recalcula a janela para os motoristas com dado novo, numa transação por motorista.
3. Para cada motorista: monta as jornadas pelas macros (R4–R9), mede direção pelas posições (R7), acha paradas e DSR (R15–R17), cruza telemetria (R18–R20), aplica os limites da operação (R10–R16) e grava jornada, parada, situação e eventos novos.

## Como verificar

Cenários fictícios em `tests/sql/04_motor_jornada.sql` (macros e posições inventadas, placas TST):
- [x] **V1 (R4, R5).** 06:00 início, 12:00–13:00 refeição, 17:00 fim → 11 h de amplitude, 11 h − 1 h = 10 h líquidas, situação "dentro" (atenção só acima de 10 h).
- [x] **V2 (R6).** Refeição de 3 h → 1 h volta para a jornada; refeição de 40 min → violação.
- [x] **V3 (R8, R9).** Sem fim há 10 h → em curso; sem fim há 20 h → sem fim; fim 19 h depois do início → inconsistente.
- [x] **V4 (R10, R14).** 12h30 líquidas → violação no global; 9h30 → atenção na Ipiranga e dentro no global.
- [x] **V5 (R12).** 6 h seguidas em movimento → violação de direção contínua.
- [x] **V6 (R13).** Fim 22:00, início 06:00 → interjornada 8 h, violação.
- [x] **V7 (R15, R16).** 36 h parado no mesmo lugar → DSR, contador zera; 36 h com 80 km rodados → não conta.
- [x] **V8 (R18, R19).** 30 km num dia sem jornada → conferir; outro login no veículo → conferir.
- [x] **V9 (R3).** Rodar o job duas vezes → mesmas linhas, nenhum evento duplicado (R22).
- [x] **V10 (R2).** Macro sem mapa → contada como desconhecida, cálculo segue.
- [x] **V11 (R14).** Mudar `jornada.limite_dia` da Ipiranga → só os motoristas dessa operação mudam de situação.

## Fora do escopo

A tela de Jornada (spec `jornada-painel.md`) · a ingestão da Autotrac (spec `ingestao-autotrac.md`) · Jornada Ipiranga pelo Datapar (depende da aprovação) · descida de serra e conhecimento (Rodopar) · exceção de DSR em viagem longa (a definir com a TIC).

## Em aberto

- [ ] Limites por operação da tabela R14 (Michael; pergunta 2 do Marco 1).
- [ ] Códigos de macro da Autotrac e se a Jornada Business já entrega jornada calculada (aí comparamos com a nossa). (Flávio)
- [ ] Violação de jornada vai para a Central de alertas ou só para a tela de Jornada e o cockpit? Proposta: só direção contínua acima de 5h30 com o caminhão andando vai para a Central. (Michael)
- [ ] Exceção de DSR para viagens longas: qual regra? (TIC)

Conferido em 20/11/2026: V1–V11 em `tests/sql/04_motor_jornada.sql` (cenários fictícios com códigos de macro de teste). Correção no V1: 06:00–17:00 são 11 h de amplitude, não 10. Ainda não ligado ao n8n (a chamada a `derivado.job_jornada()` entra com a ingestão da Autotrac) e sem tela (spec `jornada-painel.md`). Parâmetros por operação da tabela R14 entram quando as operações forem cadastradas; hoje só os globais.
