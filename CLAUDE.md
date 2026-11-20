# TIC · Painel Digital (Fase 1)

Portal da TIC Transportes, contratado pela MX Midas. Junta Autotrac (telemetria e jornada), Moovsec/Intelbras (câmeras) e, se aprovado, Rodopar/Datapar (ERP) num só lugar, com banco, login, alertas e agentes de IA. **Substitui por baixo os painéis HTML que o Rafael e o Natanael já validaram**: eles viram a especificação funcional.

- Roteiro do CTO (resumo): `docs/roteiro-fase1.md` · PDF original: `material-cliente/roteiro/`
- Estudo dos painéis atuais (fluxo e regras): `docs/estudo-paineis.md`
- **Plano: banco, agentes, skills, specs e perguntas ao Michael: `docs/plano.md`**
- Specs: `docs/specs/` · Decisões: `docs/decisoes/`
- Estado e pendências: skill `pendencias`

**Marcos:** 27/11 (arquitetura e achados da prova técnica) · 11/12 (demo câmera + freada com motorista e imagem) · 15/01 (homologação) · **29/01/2027 produção e aceite**. Pausa 24/12 a 10/01. 168 h.

## Pessoas (TIC)

- **André**: diretoria, dono do orçamento; maior preocupação é o custo de IA.
- **Rafael**: criou os painéis de jornada, torre e entregas; quer continuar ajustando (pedido de mudança vira card).
- **Natanael**: frota/OPI; faz as OPIs e o resumo de violações; valida a triagem da IA.
- **Flávio**: TI da TIC (API Autotrac, firewall do servidor Moovsec).
- **Michael Fukuda**: CTO MX Midas, homologa. **Marcus**: dev.

## Regras inegociáveis

1. **Nenhum deploy apaga dado.** Migrations numeradas e só aditivas; backup antes de migration em produção.
2. **Regra de negócio em código ou banco, nunca no prompt.** IA só para imagem e julgamento. Limites ficam na tabela `parametro` (com escopo por operação e vigência), nunca fixos.
3. **Custo de IA sob controle:** Haiku por padrão, modelo maior só em baixa confiança, nada é analisado duas vezes, teto mensal com alerta.
4. **LGPD:** dados de motorista (nome, imagem, posição) só na VPS da TIC e na API do Claude da conta da TIC. Log de quem viu cada imagem. Desenvolvimento com dados sintéticos. `material-cliente/` nunca vai para o git; não colar conteúdo real em commits, logs ou chats.
5. **Vídeo nunca na VPS:** guardar link e 3 a 5 frames-chave por evento. Retenção de 12 meses.
6. **Credenciais** (Autotrac, Moovsec, Datapar, chave Anthropic) só no `.env` da VPS / cofre do servidor. Nunca no código, no front ou no git.
7. **Spec antes de código.** Regra que não está na spec vira pergunta, nunca invenção.
8. **Decisão difícil de desfazer** vira arquivo em `docs/decisoes/`.
9. **Projeto separado do Elysium:** mesmo padrão (Docker Compose, Caddy, n8n, migrations, testes), mas VPS, repositório, banco e credenciais próprios, em nome da TIC.

## Vocabulário da TIC

OPI (Observação para Prevenção de Incidente, formulário FFRO 005 rev5), tratativa, macro (Autotrac), DSR (descanso semanal de 35 h), interjornada, RDO, conjunto (cavalo + semi), torre, grade (janela de descarga), operação (Ipiranga, OPASC, Araucária…), central (operador que recebe alertas).

## Convenções

- Datas no banco em **UTC**; fuso de negócio `America/Sao_Paulo`.
- Ponto de encontro entre fontes: **placa do cavalo + horário**, com tolerância de desvio de relógio medida.
- Textos de interface em português do Brasil.
