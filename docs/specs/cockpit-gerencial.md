# Spec do Cockpit gerencial

**Status:** primeira entrega publicada · **Marco:** 3b · **Atualizada em:** 2026-11-27

[Abrir o protótipo com dados fictícios](prototipo-cockpit-gerencial.html).

**Tela:** Painéis → Cockpit gerencial (`/cockpit`) · **Fontes:** `bruto.autotrac_evento`, `cadastro.veiculo` e estado da Telemetria · **Workflow:** `api-cockpit` · **Função:** `sp_cockpit_resumo`

## O que faz

Mostra à operação, à frota e à diretoria como os eventos de condução variam ao longo do período. A primeira entrega usa os dados que a Telemetria da Autotrac já grava e segue a estrutura de filtros, tendência e distribuição por tipo do mockup de indicadores.

## Regras

- **R1.** Reutilizar a permissão `cockpit.ver` e o escopo de operações aplicado em Condução. O servidor calcula os totais somente com veículos visíveis à pessoa.
- **R2.** Reutilizar os períodos de [Condução](relatorio-conducao.md): hoje, últimos 7 dias (padrão), mês atual e mês anterior. Datas e agrupamentos seguem `America/Sao_Paulo`. Permitir filtrar por operação, placa e tipo de evento.
- **R3.** Contar os mesmos tipos de condução da primeira entrega de Condução. Cada evento registrado conta uma vez. Exibir o total no período, a evolução por dia e a distribuição por tipo, aplicando os mesmos filtros aos três indicadores.
- **R4.** Exibir o horário da última coleta concluída da Telemetria e seu estado. Se a consulta for bem-sucedida e os filtros não encontrarem registros, mostrar total zero e uma mensagem de vazio. Falhas de consulta exibem uma mensagem de erro com opção de tentar novamente.
- **R5.** A tela lê os dados pelo portal. A rotina atual de ingestão da Autotrac segue alimentando o banco de forma independente.
- **R6.** Exibir os cinco motoristas identificados com mais eventos no recorte, em ordem decrescente por total. Identificar pelo cadastro ou código Autotrac, listar as placas e indicar motorista sem cadastro. As ocorrências sem código ou vínculo continuam nos gráficos e são contadas separadamente do ranking. O limite fica em `cockpit.motoristas_no_ranking`.
- **R7.** Permitir expandir o ranking inteiro, buscar por nome ou placa e alternar para a visão de veículos. O ranking de veículos inclui eventos sem motorista. Abrir um motorista ou veículo em Condução com os filtros de período, operação e tipo aplicados no Cockpit.

## Quem pode

Diretoria, operação, frota/OPI e admin, conforme os perfis que têm `cockpit.ver`.

## Fluxo

1. A pessoa abre `/cockpit` e vê o resumo dos últimos 7 dias.
2. Ao aplicar filtros, a tela chama `GET /api/cockpit/resumo`. O n8n valida a sessão e a permissão e encaminha a consulta ao PostgreSQL.
3. O PostgreSQL retorna total, série diária, totais por tipo e estado da coleta. A tela apresenta os mesmos valores nos gráficos e nos respectivos rótulos.

## Como verificar

- [ ] **V1 (R1).** Sem sessão → 401. Perfil sem permissão → 403. Veículos de outra operação ficam fora do total e das séries.
- [ ] **V2 (R2).** Combinar período, operação, placa e tipo. Conferir registro próximo à meia-noite no horário de Brasília.
- [ ] **V3 (R3).** Com dados fictícios, o total bate com a soma da série diária, a soma por tipo e a consulta de Condução com filtros equivalentes. Ignição, eventos temporizados e tipos desconhecidos ficam fora.
- [ ] **V4 (R4).** Conferir carregamento, vazio, erro e atraso de coleta. Uma falha de consulta não aparece como zero eventos.
- [ ] **V5 (R5, manual).** Comparar o resumo com o banco local e, após publicação, repetir com dados reais. Conferir o layout em 390, 768, 1366 e 1920 px.
- [x] **V6 (R6).** Na API local autenticada, a placa fictícia retornou 72 eventos, com 36 e 18 nos dois primeiros motoristas e 18 sem identificação. Ao filtrar freada brusca, as posições ficaram com 12 e 6 eventos.
- [ ] **V7 (R7).** Teste autenticado local: filtro de freada retornou 24 eventos pela placa e 12 pelo primeiro motorista, exatamente os totais do ranking, e zero com outra operação no filtro. Na VPS, 182 motoristas e 172 veículos no recorte de sete dias; as somas reconciliaram com 34.092 eventos. Conferência visual autenticada e teste com dois perfis operacionais ficam pendentes.

Em 27/11, o teste autenticado local verificou 72 eventos no total e nas duas séries, 24 por tipo e zero com o filtro de operação sem correspondência. Condução continuou retornando a primeira página. Na VPS, o total e as somas das duas séries bateram em 29.012 eventos. A página respondeu 200 e a API sem sessão respondeu 401. A conferência visual autenticada e o teste com perfis de operações diferentes ficaram pendentes.

## Fora da primeira entrega

Gravidade e tempo de resposta a alertas, reincidência, conformidade OPI, recomendações da IA e consumo de IA.

Na revisão visual publicada, a série diária da API é agrupada por semana no gráfico. Os cartões e painéis do mockup que dependem de outras fontes exibem o estado pendente.

Na validação da revisão em produção, o recorte de sete dias retornou 33.299 eventos, cinco motoristas no ranking e 733 eventos sem identificação. O frontend respondeu 200 e a API sem sessão respondeu 401. A conferência visual autenticada em produção ficou pendente.

## Em aberto

- [ ] **Eventos graves:** aprovar o mapa de eventos que geram alertas e sua gravidade. [Spec da Central e Telemetria](correlacao.md).
- [ ] **Tempo médio de resposta:** definir se a medição termina na primeira ação ou no encerramento da tratativa e validar com alertas reais.
- [ ] **Reincidência:** definir os tipos, o intervalo e o número de repetições. O ranking atual usa total de eventos.
- [ ] **Falsos positivos evitados:** validar a triagem por IA e a fórmula do indicador com as revisões da Central.
- [ ] **Conformidade OPI:** integrar as avaliações validadas e definir o recorte da média.
- [ ] **Jornada e consumo de IA:** completar, respectivamente, a coleta ATIC e o registro de consumo das análises.
