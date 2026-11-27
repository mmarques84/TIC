# Spec: Relatório de condução por motorista

**Status:** rascunho (para aprovação do Marcus) · **Marco:** 3b (novo, sugerido em 26/11/2026) · **Atualizada em:** 2026-11-26
**Telas:** nova tela "Condução" (layout a criar e aprovar antes de codar) · **Tabelas:** lê `bruto.autotrac_evento`, `cadastro.motorista`, `cadastro.veiculo`, `controle.evento_mapa`; grava `controle.auditoria` (exportação) · **Workflows:** `api-conducao` (novo) · **Funções:** `sp_conducao_ranking`, `sp_conducao_motorista`

## O que faz

Mostra, por motorista e por caminhão, **como a frota está sendo conduzida**, a partir dos eventos de telemetria que a Autotrac já manda ao painel (≈ 30 mil por dia): velocidade excessiva, RPM excessiva, fora da faixa verde, marcha lenta excessiva, banguela, aceleração e freada bruscas, pressão do óleo. A equipe de frota/OPI e a operação usam para **orientar o motorista**, escolher quem precisa de OPI/treinamento e acompanhar a evolução. Não é alerta em tempo real (isso é a Central): é o retrato da semana ou do mês.

## Regras

**Quem vê**
- **R1.** Ver exige a permissão nova `conducao.ver`. Proposta: diretoria, operação, frota/OPI e admin veem; central e TI não (em aberto).
- **R2.** Cada pessoa vê só os veículos das operações dela (veículo sem operação aparece para todos), como nas outras telas.

**Período e filtros**
- **R3.** Período: hoje, últimos 7 dias (padrão), mês atual ou mês anterior. Dia de São Paulo. A Autotrac guarda 7 dias, mas o painel guarda o histórico: meses anteriores vêm do banco do painel.
- **R4.** Filtros: tipo de evento (todos os de condução, ou um), operação, busca por motorista ou placa.

**Ranking (tabela principal)**
- **R5.** Uma linha por motorista, com: nome (o do cadastro do painel; sem cadastro, o nome e o código que vêm da Autotrac, com a marca "não cadastrado"), caminhões que dirigiu no período, **total de eventos de condução**, e uma coluna por tipo (velocidade, RPM, fora da faixa verde, marcha lenta, banguela, aceleração brusca, freada brusca).
- **R6.** Colunas de tempo quando o evento tem início e fim: **minutos fora da faixa verde** e **minutos em marcha lenta**.
- **R7.** **Km rodados** no período, pelo hodômetro dos eventos da Autotrac, e **eventos por 100 km** (para não comparar quem rodou 50 km com quem rodou 3.000 km). Sem km suficiente: "—".
- **R8.** Ordem padrão: eventos por 100 km, do maior para o menor; outras ordens: total, velocidade, nome.
- **R9.** Não entram no relatório: "temporizado", ignição ligada/desligada (não são condução) e "desconhecido" (até a Autotrac explicar os números 26–49). Pressão do óleo entra só na visão por caminhão (R11), não no ranking do motorista.
- **R10.** Nenhuma cor sozinha: o destaque de quem está acima da média vem com o texto ("2,3× a média da frota").

**Visões**
- **R11.** Alternar a tabela entre **por motorista** e **por caminhão** (mesmas colunas; por caminhão inclui pressão do óleo baixa/alta).
- **R12.** Abrir a linha de um motorista: eventos por dia no período (gráfico), os caminhões, e os últimos 50 eventos (hora, tipo, velocidade, local).

**Exportar**
- **R13.** Botão "Baixar planilha" (CSV) do que está na tela. Grava `controle.auditoria` (`conducao.exportar`), com quem e o filtro.

**Dados**
- **R14.** O relatório só lê o que já está no banco (ingestão da Autotrac); nada é buscado na Autotrac na hora.
- **R15.** Mostra "Dados até HH:MM" (último evento recebido) e o aviso quando a ingestão está atrasada (estado da integração, como no Início).

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver o relatório | ✅ | ✅ | ✅ | — | — | ✅ |
| Baixar planilha | ✅ | ✅ | ✅ | — | — | ✅ |

## Fluxo

1. `GET /api/conducao/ranking?periodo=&visao=&tipo=&q=` → `sp_conducao_ranking`.
2. `GET /api/conducao/motorista?codigo=&periodo=` → `sp_conducao_motorista` (detalhe, R12).
3. `GET /api/conducao/exportar?...` → mesmo ranking em CSV + auditoria (R13).

## Como verificar

- [ ] **V1 (R1, R2).** Central e TI: 403. Operação A não vê caminhão da operação B.
- [ ] **V2 (R5, R9).** Com eventos fictícios, as contagens por tipo batem com contagem direta; temporizado, ignição e desconhecido não entram.
- [ ] **V3 (R6, R7).** Minutos de marcha lenta = soma das durações; eventos por 100 km correto; sem km = "—".
- [ ] **V4 (R5).** Motorista sem cadastro aparece com nome e código da Autotrac e a marca "não cadastrado".
- [ ] **V5 (R8).** Ordem padrão por eventos/100 km.
- [ ] **V6 (R13).** Exportar gera CSV com as mesmas linhas e grava a auditoria.
- [ ] **V7 (manual).** Na VPS, com os dados reais: os 167 motoristas da Autotrac aparecem; a tela abre em menos de 3 s para 30 dias.

## Fora do escopo

Nota ou "score" do motorista (fórmula de pontuação é decisão da TIC, ver Em aberto) · gerar OPI a partir do relatório (spec `opi.md`) · alertas em tempo real (Central) · consumo de combustível em litros (a Autotrac manda nível de tanque em alguns eventos; ver depois).

## Em aberto

- [ ] **Quem vê:** central e TI precisam ver? (Michael)
- [ ] **Onde fica no menu:** novo item "Condução" em Painéis (muda a ordem do Roteiro V2) ou dentro do Cockpit OPI? (Michael)
- [ ] **Pontuação:** a TIC quer uma nota por motorista (ex.: pesos por tipo de evento)? Se sim, os pesos são dela. Até lá, só contagens e por 100 km. (Rafael / Natanael)
- [ ] **Significado exato dos campos da Autotrac:** `VelocityMax` em velocidade excessiva (a média real veio 24, estranho para excesso) e a duração dos eventos. Conferir com a Autotrac antes de mostrar velocidade no relatório.
- [ ] **De-para de motoristas:** os 167 códigos da Autotrac precisam virar motoristas do cadastro (por planilha do RH ou carga a partir da Autotrac, como foi com os veículos). Até lá o relatório funciona com o nome da Autotrac (R5).
