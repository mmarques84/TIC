# Estudo do que a TIC já usa (20/11/2026)

Material lido: 5 painéis HTML do Rafael, 3 OPIs, e-mail "Violações 13/11" do Natanael, roteiro do Michael. Arquivos originais em `material-cliente/` (fora do git, dados reais). Aqui só regras e estrutura, sem dados de pessoas.

## Como funciona hoje

Nenhum painel tem banco nem API. Cada HTML é um **retrato**: os dados vão embutidos no próprio arquivo (`window.DADOS`, `window.__PAINEL__` ou JSON em gzip+base64). Uma rotina no Claude do Rafael entra nos portais (Autotrac, Datapar, Portran), lê e-mails, grupos de WhatsApp e planilhas do SharePoint, calcula tudo e gera o HTML de novo (entregas: de hora em hora, das 04h às 22h; Ipiranga: recarrega a cada 15 min e marca "desatualizado" depois de 3 h).

Consequências que o projeto resolve: login manual nos portais, cota do Claude Pro, nenhum histórico além de cópias de arquivo, tratativas e ajustes espalhados (banco do artefato do Claude, planilha Excel).

## 1. Painel de Jornada TIC (Autotrac)

**Pergunta que responde:** quem está em jornada agora, quem violou a lei, quem precisa de descanso semanal, quem está parado com jornada aberta.

**Fonte:** Autotrac Jornada Business (macros) + Telemetria Business (km por motorista/dia, motorista logado). Retrato de 16/11 com 158 motoristas e macros desde 02/11.

**Dado por motorista:** código Autotrac, nome, sem controle (sim/não), veículo; jornadas (início, fim, amplitude, direção, refeição, descanso, trabalho, maior direção contínua, aberta, sem fim); interjornadas (de, até, horas); paradas de 11 h+ no mesmo local (local, início, fim, horas, conta como DSR, km de telemetria no período); parado desde / horas; local atual; último DSR e dias sem DSR; último evento; status atual; sequência de macros; contagem de violações Autotrac; telemetria (km 48 h, login, outro login, km parado); alertas (`bad`, `dsr`, `conf`, `warn`); nível 0–3 e 9.

**Status do motorista:** Dirigindo, Em jornada, Em serviço, Refeição, Parada/descanso, Fora de jornada, Sem eventos.

**Violações que a Autotrac já aponta:** parada de descanso curta, refeição excedida, refeição < 1 h, direção > 5h30, jornada normal excedida, jornada estendida excedida, interjornada < 11 h, dias consecutivos (DSR).

**Regras do painel** (Lei 13.103/2015, CLT 235-C, CTB 67-C):
- Jornada 8 h + até 2 h extras (até 4 h por convenção). **Amarelo > 10 h trabalhadas; vermelho > 12 h ou jornada aberta há mais de 13 h.**
- Refeição mínima 1 h; até 2 h é descontada; o que passar volta a contar como tempo à disposição.
- Direção contínua máx. 5h30; 30 min de descanso a cada 6 h de direção.
- Interjornada 11 h seguidas a cada 24 h (STF, ADI 5322: sem fracionamento).
- DSR 35 h (24 + 11) por semana, sem acúmulo em viagem longa. **Alerta com 6 dias sem 35 h; vermelho com 7.**
- Tempo de espera conta como jornada: parado no cliente com jornada aberta pede tratativa (descanso ou espera).
- **Parado 35 h+** no mesmo lugar (raio de 1 km) = DSR provável; pede conferência se houve jornada aberta; **não conta se a telemetria mostra > 50 km** do motorista logado no período.
- Telemetria: alerta se rodou **> 20 km num dia sem jornada aberta** ou se **outro motorista está logado** no veículo.

**Tratativa (o único dado que o usuário grava):** por motorista, status entre *DSR confirmado (descanso)*, *Tempo de espera (conta jornada)*, *Macro errada – corrigir*, *Jornada correta*, *Orientado / advertido*, *Outro*; observação até 1.000 caracteres; quem e quando; retrato a que se refere. Hoje fica no banco do artefato do Claude (`tratativas`), com permissão de "Colaborador".

**Telas:** faixas por alerta (Todos, Parado 35h+, Violação, Conferir, Atenção, Em jornada, Tratados), filtro por dias seguidos sem DSR, busca, tabela com linha expansível (sequência de macros, últimas jornadas, interjornadas, paradas de 11 h+).

## 2. Jornada Ipiranga (Datapar)

**Pergunta:** horas por dia, semana (seg–dom) e mês dos motoristas da operação Entrega Ipiranga.

**Fonte:** Datapar › Macro Lançamento. Códigos de macro: **1 início de jornada, 2 início de refeição, 7 fim de refeição, 5 início de parada, 3 fim de jornada.**

**Regras:**
- Jornada líquida = fim − início − refeição − paradas. Conta no dia em que começou.
- **Limites: 10 h/dia, 60 h/semana; atenção a partir de 52 h na semana**; atenção no dia a partir de 9 h.
- Interjornada < 11 h = alerta.
- Jornada sem "fim" lançada há até 16 h = em curso; depois disso = "sem fim de jornada" e não soma horas.
- Mais de 18 h entre início e fim = "verificar: fim lançado após 18h" (inconsistente, não soma).
- Dias trabalhados = dias com início de jornada; dias seguidos.

**Telas:** Diário, Semana (mapa de calor), Totalizador do mês; KPIs clicáveis (com jornada no dia, em jornada agora, > 10 h no dia, > 60 h semana, ≥ 52 h semana, interjornada < 11 h, sem fim); histórico do motorista em diálogo.

## 3. Torre de Chegadas (Datapar + Autotrac)

**Pergunta:** quais carretas carregadas vão chegar depois da agenda de descarga.

**Fonte:** Datapar, torre "Acomp. Carreta", documentos tipo **MF**; agenda = Data Descarga (sem agenda, usa a Previsão Real da Datapar). Posição e jornada da Autotrac.

**Dado por carreta:** placa, motorista, região, produto, NF, origem, destino, cliente, local, última posição, agenda, previsão Datapar, dias sem DSR, observação da torre, fonte da jornada, jornada (texto), libera em, fase, km restante, ETA, motivo, status, fonte do ETA, agenda vencida, atraso em horas.

**Cálculo da previsão:** distância pela estrada até a cidade de destino; **60 km/h de média; até 11 h de direção por jornada** (2 h para refeição e paradas); **só roda das 05h às 21h; jornada máxima de 13 h; 11 h de interjornada** antes de voltar. Início de jornada e descanso vêm da Autotrac; sem controle de jornada = descansado, saindo às 05h. Posição ou destino não localizado → usa previsão Datapar e explica no "motivo".

**Status:** ATRASADO (previsão depois da agenda, ou > 3 h depois da previsão Datapar sem agenda) · RISCO (folga < 2 h) · NO HORÁRIO · CHEGOU ATRASADO (já registrou chegada depois da agenda) · NO DESTINO (chegou no prazo, aguardando descarga) · SEM DADOS. Visual de "quadro de aeroporto", próprio para TV.

## 4 e 5. Painéis de Entregas OPASC e Araucária (backlog no roteiro)

**Pergunta:** cada nota fiscal do dia foi entregue? Com que evidência? Qual a previsão para o cliente?

**Fontes:** Portran (NFs; OPASC transportador 2262, bases Itajaí 6375, Biguaçu 6377, Guaramirim 6379; Araucária transportador 1305, dependência 6370) · e-mails "Programação PRÉ / D+1 / D - Base …" (ordem e grade; vale a versão mais recente por placa e viagem) · Autotrac (áreas de cliente, paradas, saída da base) · grupos de WhatsApp de entrega (só leitura: previsão do motorista e aviso de chegada) · planilhas SharePoint: "RELAÇÃO ATUALIZADA 2026" (carreta → cavalo), "ATENDIMENTO ARAUCARIA" (rede e observações do cliente, ex.: precisa de mangote), `observacoes_entregas.xlsx` (ajuste manual) · RDO do dia (Op/Inop, abertura de jornada × saída real da matriz) · OpenStreetMap (endereço do cliente).

**Status da NF:** ENTREGUE (passou pela área do cliente ou parou na referência com o nome do cliente, depois de sair da base) · NO CLIENTE · PROVÁVEL (cliente sem área; parada longa perto do endereço, **decisão do Claude**, ou aviso de chegada no WhatsApp) · VERIFICAR · NÃO ENTREGUE (só manual) · EM ROTA · NA BASE.

**Previsão:** a partir da saída da base, **50 km/h**, distância em linha reta × 1,3, **1 h em cada cliente**; recalcula quando chega ou passa de 1 h num cliente.

**Alertas:** fora da grade, atrasado, entregue fora da sequência, placa trocada, NF fora da programação, pedido programado sem NF, próximas viagens. Aviso quando Portran, programação ou Autotrac falharam na última rodada.

**Ajuste manual:** planilha com NF, status manual, observação, responsável; o painel marca "Informação manual" e mostra o que a Autotrac indicava.

**Aba "Para clientes":** uma linha por produto, sem motorista nem evidência; status traduzido (Entregue/Provável → ENTREGUE; Na base → EM CARREGAMENTO; Verificar → EM ANDAMENTO); copiar tabela ou baixar imagem para mandar ao cliente.

## 6. Resumo de violações (e-mail diário do Natanael)

Enviado a ~16 destinatários internos. Eventos validados por motorista, separados em **Frota Viagem** e **Frota Entrega**: velocidade, chuva, freada brusca, ponto crítico, acesso, alça, serra vazio descendo. Gráfico do período (~3 semanas) e ranking de motoristas com selo (vermelho / amarelo / verde). Marcha lenta e aceleração lateral com frase de resumo. Anexo: vídeo da freada brusca. É o embrião do **cockpit gerencial**.

## 7. OPI (formulário)

- **Atual: FFRO 005 rev5 (17/08/2026).** Itens 1–35 e 37–43: **não existe item 36** (42 itens no total). Itens 38–43 (câmeras de fadiga, frontal, laterais, interna, informações na imagem) só para OPI não anunciada. Item 12 novo ("interação com objetos com o veículo ligado").
- **Antigo: FOPE 016 rev02 (2023), 38 itens.** O exemplo "OPI SEM CINTO" está nele.
- Cabeçalho: anunciada / não anunciada, motorista, data, frota, placa cavalo, placa semi, km e hora inicial/final, local.
- Cada item: SIM (atendido) / NÃO (não atendido) / N.A. Rodapé: itens avaliados, atendidos, % de atendimento; ocorreu a infração? é reincidente? observação; ação (orientação, advertência verbal, advertência escrita, suspensão, desligamento, N.A.); imagens das câmeras; feedback; assinaturas (motorista, supervisor, avaliador), aprovado sim/não, data.
- **Itens com sentido invertido** (a pergunta descreve o problema, então "SIM" é ruim): "apresenta sinais de fadiga e sono", "parou em local não autorizado", e no formulário antigo "ocorre pulo no tempo da gravação". O agente e o cálculo precisam tratar a polaridade por item.
- **Erros de preenchimento manual encontrados:** item marcado NÃO com total "29 de 29 = 100%"; OPI com motorista sem cinto e "Ocorreu a infração? NÃO". **Percentual e infração devem ser calculados, não digitados.**
- Janela real de 15 a 27 min; a TIC guarda o vídeo com o nome da OPI.

## Divergências entre fontes (viram parâmetro ou pergunta)

| Tema | Jornada TIC | Ipiranga | Torre | Entregas | Roteiro |
|---|---|---|---|---|---|
| Limite diário | amarelo > 10 h, vermelho > 12 h (ou aberta > 13 h) | 10 h (atenção 9 h) | máx. 13 h | — | 8 + 2 (até 4) |
| Semana | — | 60 h (atenção 52 h) | — | — | 60 h de direção |
| DSR | alerta 6 dias, vermelho 7 | — | — | — | alerta a partir do 7º |
| Velocidade média | — | — | 60 km/h, 05h–21h | 50 km/h, reta × 1,3, 1 h/cliente | — |
| Fonte da jornada | Autotrac | Datapar | Autotrac | RDO | — |
