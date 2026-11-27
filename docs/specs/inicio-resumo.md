# Spec: Início com dados reais (resumo)

**Status:** implementada (26/11/2026; spec aprovada pelo Marcus em 26/11) · **Marco:** 2 · **Atualizada em:** 2026-11-26
**Telas:** a tela Início já existe e foi aprovada (canvas "TIC Painel Digital · Login", artboard Início); muda só a origem dos dados · **Tabelas:** lê `derivado.alerta`, `derivado.evento`, `derivado.motorista_situacao`, `derivado.jornada`, `derivado.tratativa`, `ia.triagem`, `ia.opi`, `ia.consumo`, `controle.credencial_status`, `bruto.ingestao_lote`, `bruto.autotrac_evento` · **Workflows:** `api-inicio` (novo) · **Funções:** `sp_inicio_resumo`

## O que faz

Tira os números de exemplo do Início e mostra o retrato real do momento, lido do banco: alertas abertos, jornada, OPI, consumo de IA e a situação das integrações (Autotrac, Moovsec, IA, Datapar). Cada perfil continua vendo os seus 4 indicadores e o seu painel lateral, como na tela aprovada. Enquanto uma fonte ainda não tem dado (ex.: alertas sem a correlação, jornada sem a ATIC), o número aparece como **0 ou "—" com o motivo escrito**, nunca inventado.

## Regras

**Quem vê**
- **R1.** Todo usuário logado vê o Início. Cada bloco só aparece com a permissão da tela de origem (alertas: `alerta.ver`; jornada: `jornada.ver`; OPI: `opi.ver`; consumo: `consumo_ia.ver`; integrações: `integracao.ver`).
- **R2.** Alertas, jornada e OPI respeitam as operações da pessoa (como nas telas de origem).

**Indicadores (cartões do topo)**
- **R3.** *Alertas abertos*: alertas em aberto ou em tratamento; nota = quantos críticos.
- **R4.** *Fadiga na última hora*: alertas de fadiga criados na última hora; nota = sirenes acionadas na última hora.
- **R5.** *Motoristas em jornada*: motoristas com jornada aberta agora; nota = "de N cadastrados".
- **R6.** *Violações de jornada hoje* (dia de São Paulo): jornadas do dia em violação; nota = quantas com tratativa.
- **R7.** *Falsos positivos evitados*: dos alarmes de hoje com triagem da IA, % que a IA marcou como falso; sem triagem hoje = "—" com nota "sem triagem hoje".
- **R8.** *OPIs do mês*: OPIs do mês concluídas / motoristas com OPI prevista; nota = aguardando validação. Sem OPI = "—".
- **R9.** *Consumo de IA no mês*: % do teto do mês (parâmetro); sem teto definido = "—" com nota "teto não definido".
- **R10.** *Integrações*: fontes funcionando / fontes ativas. Uma fonte está **ok** se teve sucesso nos últimos `autotrac.alerta_sem_dados_min` (30 min); **atraso** se o último sucesso é mais antigo; **erro** se a credencial foi recusada (401/403); **inativa** se nunca foi configurada. Nota = a primeira fonte com problema.

**Painéis**
- **R11.** *Alertas que pedem ação*: os 5 alertas abertos mais graves e mais antigos, com nível escrito, título, placa, motorista e "há X min".
- **R12.** *Integrações* (lateral): uma linha por fonte com o estado (R10) e o texto: Autotrac = "último dado há X min · N eventos hoje"; fonte inativa = "não configurada".
- **R13.** *Jornada* (lateral da operação): até 5 motoristas em violação ou "conferir", do mais grave. *OPI* e *Consumo*: as linhas das telas de origem (vazio = "nada pendente").
- **R14.** Sem dado = mostra 0 / "—" e a frase do motivo (ex.: "aguardando a correlação de alertas", "aguardando a API ATIC"). Nunca número de exemplo.

**Atualização**
- **R15.** A tela consulta a cada 30 s (era 5 s no protótipo; o resumo junta várias tabelas). Mostra "Atualizado às HH:MM:SS".

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver o Início (blocos conforme R1) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Fluxo

1. `GET /api/inicio` → `sub-autorizar` (sessão, sem permissão específica) → `sp_inicio_resumo(usuario)` → JSON no formato que a tela já usa (`ResumoInicio`).
2. A função monta só os blocos que o perfil pode ver (R1, R2).
3. No front, `DADOS_FICTICIOS.inicio = false`: some o aviso amarelo de "dados de exemplo".

## Como verificar

- [x] **V1 (R1, R2).** Perfil TI não recebe alertas; operação de outra operação não vê o alerta da operação alheia.
- [x] **V2 (R3–R6).** Com dados fictícios de teste (alertas, jornadas, tratativas), os números batem com contagem direta nas tabelas.
- [x] **V3 (R7–R9).** Sem triagem, sem OPI e sem teto: "—" com a nota do motivo.
- [x] **V4 (R10, R12).** Autotrac com sucesso há 5 min = ok; há 2 h = atraso; `senha_mudou` = erro; Moovsec nunca configurado = inativa.
- [x] **V5 (R11).** Ordem: crítico antes de grave; dentro do nível, o mais antigo primeiro; no máximo 5.
- [x] **V6 (R14).** Banco vazio: a tela abre sem erro, sem nenhum número de exemplo.
- [x] **V7 (manual).** Na VPS, a Autotrac aparece "ok · último dado há X min · N eventos hoje".

## Fora do escopo

Gráficos do Cockpit gerencial · clicar no indicador e abrir filtrado (já leva à tela de origem pelo link "Abrir") · contar eventos brutos da Autotrac como "alertas" (isso é a correlação, outra spec).

## Em aberto

- [ ] Para a diretoria, "falsos positivos evitados" deve contar o dia ou o mês? (André)
- [ ] "N cadastrados" em *Motoristas em jornada*: todos os motoristas ativos ou só os com controle de jornada? (Rafael) — até lá, só os com controle.

Conferido em 26/11/2026: V1–V6 em `tests/sql/09_inicio.sql` (9/9 conjuntos ok); rota `GET /api/inicio` local com sessão de teste. V7 na VPS (26/11 21:12): Autotrac · Telemetria "ok · último dado há 7 min · 34126 eventos hoje"; demais cartões 0 ou "—" com o motivo. As fontes aparecem como Autotrac · Telemetria, Autotrac · ATIC, Moovsec, IA (Claude) e Datapar.
