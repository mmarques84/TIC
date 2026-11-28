# Fontes dos painéis atuais da TIC

Levantamento informado pela TIC em 26/11/2026. Os horários e estados abaixo descrevem as rotinas existentes naquela data. Este documento serve de referência para as specs de cada funcionalidade.

## 1. Jornada Ipiranga

- **Rotina ativa** às 07h, 11h, 15h e 19h.
- **Fonte única** é a API de macros do Rodopar/Datapar, restrita à operação `TIC - Entregas`.
- **Dados** incluem ID e data/hora da macro, código e nome do motorista, veículo e operação.
- **Histórico** de 12 meses mantido pela união do HTML anterior, do `historico_jornada.json` e dos novos registros, com deduplicação. A fonte guarda cerca de 10 dias.

## 2. Jornada TIC (Lei 13.103)

- **Rotina ativa** em dias úteis às 09h30.
- **Autotrac Jornada (`/svj`)** fornece macros dos últimos 14 dias, consultadas por motorista. Inclui início e fim de jornada, direção, refeição, descanso e espera, com data/hora e local.
- **Autotrac Telemetria Business** fornece km por motorista por dia nos últimos 7 dias. A pasta `_rotina` fornece scripts, painel anterior e tratativas.
- **Cálculos** incluem estouros de jornada e interjornada, parada de 35 h ou mais, violação, conferir, atenção e em jornada. A rotina calcula dias consecutivos sem DSR com a regra de 35 h no mesmo local e até 5 km de telemetria. Também identifica caminhão rodando sem jornada aberta ou com outro motorista.

## 3. Entregas OPASC

- **Rotina pausada**. Executava no minuto 37, das 04h às 22h. Cobre Ipiranga Itajaí, Biguaçu e Guaramirim, transportador 2262.
- **Programação e entregas** usam anexos do Outlook (`Programação PRÉ/D+1/D – Base …`), leitura de três grupos de entrega no WhatsApp Web e NFs do dia no Portran (`transp2262`).
- **Apoio** vem da planilha `RELAÇÃO ATUALIZADA 2026` (frota por operação), de `observacoes_entregas.xlsx`, do Autotrac Supervisor (última posição e paradas por cavalo) e do Nominatim (geolocalização de clientes).
- **Resultado** é o status por NF, incluindo `ENTREGUE` ou `PROVÁVEL` quando há parada de pelo menos 20 minutos junto ao cliente após a saída da base.

## 4. Entregas Araucária

- **Rotina pausada**. Executava no minuto 7, das 04h às 22h.
- **Fontes e regra de entrega** seguem o OPASC, com programação restrita à `Base ARAUCARIA`, anexo do e-mail RDO Araucária e planilha adicional `ATENDIMENTO ARAUCARIA.xlsx`.
- **Alerta adicional** é enviado por e-mail somente ao Kauan quando um caminhão fica parado mais de 30 minutos no cliente.

## 5. Torre de Chegadas TIC

- **Rotina pausada**. Executava no minuto 40 a cada duas horas, das 04h às 20h.
- **Torre Acomp.Carreta (Rodopar/Datapar)** fornece somente carretas carregadas (MF), com placa, motorista, local atual, origem, destino, status da viagem, agenda de descarga, nova previsão, interjornada de 11 h, última DSR, produto e NF.
- **Autotrac Jornada** fornece início da jornada, interjornada, status atual e horas de direção por motorista. **Nominatim e OSRM** fornecem a distância restante.
- **Previsão** considera trânsito das 05h às 21h, jornada de 13 h, interstício de 11 h e velocidade média de 60 km/h. Classifica cada carreta como atrasado, risco, no horário, chegou atrasado ou no destino.

## Dependências a validar na migração

O acesso ao SQL Server do Datapar foi informado em 26/11/2026. Em 27/11, a tentativa TCP da VPS para a porta 15779 não abriu conexão em oito segundos. Confirmar com o responsável pelo Datapar a liberação do IP de saída da VPS e a porta da instância `DW_TIC`. Depois, validar a autenticação e identificar os objetos que entregam os dados da API de macros e da Torre Acomp.Carreta.

A Jornada TIC e a Torre dependem de dados de jornada da Autotrac. OPASC e Araucária usam a Autotrac para posição e paradas. A Jornada Ipiranga depende exclusivamente do Rodopar/Datapar. Na migração, é preciso comparar os campos e a cobertura dos serviços atuais com os da Telemetria e da ATIC do projeto.

Na VPS, a Telemetria já grava eventos. A última tentativa de cadastro de frota da ATIC retornou HTTP 500. Confirmar o código da conta e a habilitação da ATIC antes de ativar a coleta periódica de posições, macros e logins.
