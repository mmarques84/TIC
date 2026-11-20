---
name: pendencias
description: Estado do projeto TIC Painel Digital (TIC Transportes, MX Midas, Fase 1) e lista do que falta para retomar o trabalho. Use quando o usuário disser "vamos voltar onde parei", "o que falta", "pendências", "status do TIC" ou abrir o projeto em outra máquina.
---

# Pendências do TIC Painel Digital

Ao retomar: leia `CLAUDE.md`, `docs/plano.md`, `docs/estudo-paineis.md` e esta lista antes de agir, e confirme com o Marcus por onde seguir. Ao terminar uma sessão de trabalho, atualize o "Diário" (data, o que mudou, o que não foi verificado).

## Estado atual (20/11/2026)

- **Etapa:** fim da 0 (setup e estudo, até 24/11) e começo da 1 (prova técnica, 20/11 a 04/12). **Marco 1 em 27/11:** arquitetura e achados da prova técnica.
- **Feito:** repositório local criado (sem commit, sem GitHub), material do cliente em `material-cliente/` (fora do git), estudo dos 5 painéis, plano (banco, agentes, skills, specs), decisão 001 proposta.
- **Stack decidida (20/11):** PostgreSQL 17 + PostGIS (decisão 001), arquitetura clean com domínio no banco e n8n como adaptador (decisão 002), Angular, Caddy. Montagem em `docs/montagem.md`. Skills `nova-funcionalidade`, `tela-tic`, `regras-jornada` criadas.
- **VPS:** criada pelo Marcus na Hostinger (20/11); endereço, IP e titular da conta ainda não registrados aqui. Nada instalado. GitHub ainda não existe.

## Próximos passos

1. Mandar ao Michael as perguntas de `docs/plano.md` §1 e a decisão 001.
2. Criar repositório no GitHub e VPS Hostinger em nome da TIC (quem cria a conta?).
3. Parser do CSV do Moovsec (assim que o export chegar) com dados sintéticos nos testes.
4. Prova técnica Autotrac: autenticação, busca incremental, mensagem e sirene em veículo de teste.
5. Copiar e adaptar do Elysium as skills `nova-funcionalidade` e `tela-tic`; escrever `regras-jornada`.
6. Spec `seguranca-acesso.md`.

## Aguardando a TIC

- [ ] Documentação e credenciais de teste da API Autotrac (Flávio, 25/11)
- [ ] Resposta da Intelbras ou firewall do servidor Moovsec para o IP da VPS (Flávio, 25/11)
- [ ] Export CSV do Moovsec e export de alertas Autotrac do mesmo dia (Rafael, 25/11)
- [ ] `validacao-alertas-tic.html` e vídeo de uso dos painéis (Rafael / André, 24/11)
- [ ] OPIs preenchidas e vídeos de 15 min no SharePoint (Natanael, 27/11)
- [ ] Teto mensal de consumo de IA (André, 27/11)
- [ ] Parametrização de desvios e limites operacionais (pasta Midas/TIC Transportes/Artefatos do cliente)

## Aguardando o Michael

- [ ] Perguntas do `docs/plano.md` §1 (Datapar × torre, limites por operação, tratativas, pgvector, itens da OPI, e-mail de violações, operações)
- [ ] Aval da decisão 001
- [ ] Proposta de horas adicionais do Rodopar/Datapar

## Diário

- **20/11/2026 (estudo e plano):** lidos roteiro v1, 3 OPIs (FFRO 005 rev5 e FOPE 016 rev02), e-mail de violações 13/11 e os 5 painéis HTML (Jornada TIC, Jornada Ipiranga, Torre, Entregas OPASC e Araucária). Escritos `docs/roteiro-fase1.md`, `docs/estudo-paineis.md`, `docs/plano.md`, decisão 001 (proposta), índice de specs. **Não feito:** commit, GitHub, VPS. Achados principais: Torre e Ipiranga dependem do Datapar (fora do obrigatório); limites diferentes por operação; FFRO 005 não tem item 36 e tem itens de polaridade invertida; percentual da OPI precisa ser calculado.
