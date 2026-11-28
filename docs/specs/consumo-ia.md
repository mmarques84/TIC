# Spec: Consumo de IA

**Status:** rascunho (28/11/2026) para aprovação do Marcus · **Marco:** 3b · **Atualizada em:** 2026-11-28
**Telas:** "Consumo de IA" (layout a criar e aprovar antes de codar) · **Tabelas:** lê `ia.consumo`, `ia.triagem`, `ia.opi`, `controle.parametro`; grava `controle.parametro` (teto, com auditoria) · **Workflows:** `api-consumo-ia` (novo) · **Funções:** `sp_consumo_ia_resumo`, `sp_consumo_ia_teto`
**Base:** roteiro v1 (critério de aceite 5: "Consumo de IA do mês no painel, com alerta antes do teto"), plano §IA (orquestrador grava cada chamada em `ia.consumo`; Haiku por padrão, modelo maior só quando a regra pede), Roteiro V2 (cockpit com "consumo de IA, R$ e teto").

## O que faz

Mostra quanto a TIC está gastando com a IA no mês, em reais e em dólares, por função (triagem de alarmes, reanálise, OPI) e por modelo, com a projeção para o fim do mês e o aviso antes de chegar ao teto. Quem paga e decide o teto (diretoria/André) acompanha aqui; a TI vê se algo saiu do normal. O número vem do registro que o orquestrador grava a cada chamada da IA; a tela não consulta a Anthropic.

## Regras

**Quem vê**
- **R1.** Ver exige `consumo_ia.ver` (hoje: diretoria, TI e admin). Mudar o teto exige `parametro.editar` (admin), com auditoria.

**Números**
- **R2.** Gasto do mês (dia 1 até agora, horário de São Paulo) em US$ (soma de `ia.consumo.custo_usd`) e em R$ (US$ × `ia.cotacao_dolar`, parâmetro atualizado à mão; a tela mostra a cotação usada e a data).
- **R3.** Projeção do mês: gasto até hoje ÷ dias passados × dias do mês. Com menos de 3 dias de uso, a tela mostra "projeção a partir do 3º dia".
- **R4.** % do teto: gasto ÷ `ia.teto_mensal`. Sem teto definido: "teto não definido" (nunca 0%).
- **R5.** Por função (triagem, reanálise, OPI): chamadas, tokens (entrada, saída, cache), custo e custo médio por chamada. Por modelo: o mesmo.
- **R6.** Gráfico do gasto por dia no mês, com a linha do teto diário (teto ÷ dias do mês) quando houver teto.
- **R7.** Produtividade: alarmes triados e OPIs geradas no mês, e o custo por alarme triado e por OPI.

**Avisos**
- **R8.** A partir de `ia.teto_aviso_pct` (proposta: 80%) do teto, gasto ou projeção: aviso em amarelo, com texto, na tela, no Início e no Cockpit. A 100%: aviso em vermelho; o orquestrador para de chamar a IA (regra do plano) e os alarmes vão para "inconclusivo → humano".
- **R9.** Nunca só cor: todo aviso tem texto ("Projeção: 92% do teto em 30/11").

**Teto**
- **R10.** Admin define o teto em US$ e o % de aviso na própria tela; fica em `controle.parametro` com vigência (o valor antigo fica no histórico) e auditoria.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver | ✅ | — | — | — | ✅ | ✅ |
| Mudar teto e aviso | — | — | — | — | — | ✅ |

## Fluxo

1. Cada chamada da IA passa pelo orquestrador, que grava uma linha em `ia.consumo` (já existe a tabela).
2. `GET /api/consumo-ia/resumo?mes=` → `sp_consumo_ia_resumo`.
3. `POST /api/consumo-ia/teto` → `sp_consumo_ia_teto` (admin).

## Como verificar

- [ ] **V1 (R1).** Operação e central: 403. Diretoria vê, não muda o teto.
- [ ] **V2 (R2, R5).** Com consumo fictício de triagem e OPI, os totais em US$ e R$ batem com a soma e a cotação.
- [ ] **V3 (R3, R4).** Projeção correta; sem teto = "teto não definido"; com menos de 3 dias = aviso da projeção.
- [ ] **V4 (R8, R9).** 80% = aviso amarelo com texto; 100% = vermelho e o orquestrador recusa nova chamada.
- [ ] **V5 (R10).** Mudar o teto grava novo valor com vigência e auditoria; o antigo continua no histórico.
- [ ] **V6 (manual).** Tela legível a 1366 px e no celular.

## Fora do escopo

A chave da API e a cobrança (conta da TIC na Anthropic) · comparação de modelos (backlog) · gasto de outras ferramentas.

## Em aberto

- [ ] **Teto mensal em US$** (André).
- [ ] **Chave da API do Claude na conta da TIC**, criada por quem administra a conta; vai direto ao `.env` do servidor (TIC / André).
- [ ] Cotação do dólar: manual (proposta) ou buscar de uma fonte pública todo dia? (Michael)
- [ ] Quem mais vê o consumo: operação e frota/OPI também? (Michael)

**Observação:** hoje nenhuma função do painel usa IA (a triagem depende de a Central ter alertas e a OPI dos vídeos do Moovsec). A tela pode ficar pronta antes, mostrando "nenhum uso de IA no mês" até a primeira função ser ligada.
