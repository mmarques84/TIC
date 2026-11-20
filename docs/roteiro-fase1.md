# Roteiro da Fase 1 (resumo)

Fonte: "TIC - Painel Digital - Roteiro Técnico da Fase 1", Michael Fukuda, v1, novembro/2026 (PDF em `material-cliente/roteiro/`). Kick-off em 16/11/2026.

## Cenário

- 200 caminhões, ~240 motoristas, 5 câmeras por caminhão.
- Sistemas isolados: Autotrac (telemetria, jornada), Moovsec/Intelbras (câmeras), Rodopar/Datapar (ERP e jornada de uma operação), Portran (portal Ipiranga).
- 6.450 alarmes do Moovsec em 13/11, todos "Não tratado": distraído 60%, mascaramento 18%, sem cinto 14%, bocejo 7%, fadiga 0,4%, cigarro 1.
- Painéis caseiros no Claude Pro: sem banco, login manual a cada uso, cota estourada.

**Parser do Moovsec:** motorista e CPF vêm vazios (o motorista sai do login no terminal Autotrac); latitude e longitude vêm **trocadas** e com pontos de milhar (`-25.518.865`).

## Escopo obrigatório (aceite 29/01/2027)

| Bloco | Entrega |
|---|---|
| Ambiente | VPS Hostinger em nome da TIC, repositório, banco, backend, front, backup com restauração testada |
| Acesso | Login por usuário; perfis diretoria, operação, frota/OPI, TI, operador da central |
| Autotrac | Telemetria, jornada, macros, motorista logado; mensagem ao terminal e sirene |
| Moovsec | Alarmes e clipes, pelo caminho definido na prova técnica |
| Correlação | Placa + horário; evidências pesquisáveis por 12 meses |
| Triagem | Agente classifica alarme em verdadeiro / falso / inconclusivo, com confiança |
| OPI | Agente de OPI de condução (FFRO 005 rev5), validação humana por amostra, histórico exportável |
| Alertas | Escalonamento de fadiga; velocidade, freada brusca, câmera obstruída |
| Painel | Central de alertas, cockpit gerencial e OPI, jornada e torre migradas, consumo de IA |

**Extensão (horas adicionais, a aprovar):** Rodopar/Datapar somente leitura (conhecimento, carregado/vazio, motorista, destino, jornada Ipiranga). Destrava descida de serra (40/60 km/h) e motorista × conhecimento × câmera.

**Backlog:** entregas Portran + WhatsApp (Omni), OPI de descarga, novas detecções (alimentação, objeto solto, carona), alocação de cargas por jornada, OPI semanal, comparação de modelos.

## Arquitetura sugerida (o dev valida até 27/11)

VPS Hostinger (Brasil), Docker Compose, HTTPS, subdomínio em tic.com.br · PostgreSQL + pgvector, eventos particionados por mês · ingestão por n8n ou workers, Autotrac a cada 60 s (celular) tolerando 15 min (satélite), sempre incremental · vídeo nunca na VPS · motor de regras sem IA · agentes com orquestrador (Haiku por padrão) · backend com camada única de permissões, auditoria e ações · front responsivo (TV da central, computador, celular) · firewall do servidor Moovsec liberado só para o IP da VPS (Flávio).

## Regras de negócio do roteiro

**Fadiga:** mais de 4 bocejos/h (bocejo > 4 s, > 20 km/h) → mensagem no terminal + alerta no painel. Mais de 10 bocejos/h ou olhos fechados > 4 eventos/h → crítico: sirene + central. Parado, ignição desligada ou em descanso → não dispara. Alerta atrasado (sem sinal) → se já parou, só registra.

**Velocidade:** pista seca leve 81–83, médio 84–86, grave > 86 km/h · molhada (limpador) 60–63 / 64–66 / > 66 · freada brusca: queda ≥ 15 km/h em 1 s a partir de 10 km/h · força G > 0,5. OPI usa referência 75 km/h (seca) e 55 (molhada). Serra: carregado 40, vazio 60 (depende do Rodopar).

**Câmera (todas graves):** sem cinto > 10 s; celular > 10 s; fumar > 1 s; carona > 120 s e 15 km/h; objeto solto > 120 s e 20 km/h; alimentação > 10 s e 15 km/h; obstrução; distração > 5 eventos/h; mãos fora do volante > 15 s.

**Jornada:** 8 h + 2 h extras (até 4 h com acordo); direção contínua máx. 5h30 com pausa de 30 min; refeição 1 h; interstício 11 h; DSR 35 h; até 60 h de direção/semana. Contador de dias zera após 35 h parado; alerta a partir do 7º dia (exceção para viagens longas, a ajustar). Muita jornada e pouca direção = parado sem motivo; 14 h parado sem descarga programada = alerta.

**Triagem:** sempre com evidência e confiança (alta, média, baixa); sem evidência = inconclusivo → humano.
**OPI:** 1 por motorista por mês, janela de 15 min, trecho com mais alertas. Validação humana de 50% no início (começando por baixa confiança e imagem ruim); selo "validado por humano". Ações: orientação, advertência verbal, advertência escrita, suspensão, desligamento. A IA sugere; a TIC decide.

## Calendário

| Etapa | Período | Entregas |
|---|---|---|
| 0. Setup e estudo | 17/11–24/11 | VPS, Docker, Postgres, n8n, HTTPS, repositório, parser do CSV Moovsec, dicionário de dados |
| 1. Prova técnica | 20/11–04/12 | API Autotrac (telemetria, jornada, mensagem e sirene em veículo de teste); caminho do Moovsec |
| **Marco 1** | **27/11** | Arquitetura e Bill of Material (achados da prova técnica) |
| 2. Dados entrando | 30/11–11/12 | Ingestão incremental, correlação, desvio de relógio, login e perfis, subdomínio |
| **Marco 2** | **11/12** | Demo: alarme de câmera e freada brusca juntos, com motorista e imagem |
| 3a. Inteligência e painel | 07/12–23/12 | Motor de regras, triagem, OPI, escalonamento de fadiga, central de alertas |
| Pausa | 24/12–10/01 | Ingestão rodando; Michael acompanha falhas |
| 3b. | 11/01–15/01 | Cockpits gerencial e OPI, jornada e torre, consumo de IA |
| **Marco 3** | **15/01** | Homologação presencial com casos reais |
| 4. Calibração | 11/01–22/01 | Triagem × validação do Natanael; limiares; bugs |
| Treinamento | 20/01 | Michael conduz |
| **Marco 4** | **29/01** | Produção e aceite |
| Operação assistida | 01/02–12/02 | Custo, falhas de ingestão, falsos positivos |

Trello "Projeto TIC - Painel Digital": Escopo Original → Desenvolvimento Marcus → Bug → Homologação Michael → Treinamento → Aceite Cliente → Produção.

## Critérios de aceite

1. Alarme do Moovsec aparece com placa, motorista, horário e imagem, sem abrir e-mail ou portal.
2. Mais de 4 bocejos/h → mensagem no terminal; mais de 10 → sirene e central.
3. Freada brusca da Autotrac aparece com a imagem da câmera do mesmo instante.
4. OPI mensal sai preenchida no FFRO 005, com PDF e histórico pesquisável.
5. Consumo de IA do mês no painel, com alerta antes do teto.
6. Publicar nova versão não apaga dado.
7. Cada usuário vê só o que o perfil permite.

## Riscos

API do Moovsec não existe pronta (decisão por escrito no marco 1) · sirene precisa estar habilitada (testar em caminhão real) · DVR lento no 4G e trechos sem sinal · escopo (Rodopar só com horas aprovadas) · custo de IA · janela curta de 11 a 15/01 · Rafael quer seguir ajustando painéis.
