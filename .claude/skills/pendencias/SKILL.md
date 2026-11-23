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

- **20/11/2026 (Central de alertas, dados fictícios):** migration 010 (alerta: título, assumido_por, motivo do falso; mensagens padrão por tipo em parâmetros), `db/funcoes/050_central_alertas.sql` (fila, resumo, detalhe com auditoria `imagem.ver`, assumir, confirmar, falso, mensagem, sirene → `controle.fila_acao`; validação da triagem), workflow `api-central`, telas `/alertas` e `/alertas/tv`, menu com grupos recolhíveis. Dados de exemplo: `tests/dados/central-ficticio.sql` (carregar no banco local com `docker compose exec -T postgres psql -U tic_admin -d tic -c "SET ROLE tic_dono" -f - < tests/dados/central-ficticio.sql`). Testes: 5/5 SQL, 17 front, fluxo na tela. **Falta:** fotos reais (rota `central/foto` + volume), envio à Autotrac, importar a lista real de usuários.

- **20/11/2026 (motor de jornada):** migration 009 (`controle.macro_mapa` com os códigos Datapar, colunas de resultado em `derivado.jornada` e `motorista_situacao`, chave de idempotência em `derivado.evento`, 12 parâmetros) e `db/funcoes/040_motor_jornada.sql` (`derivado.job_jornada`, cálculo por motorista, direção contínua pelas posições, paradas/DSR com PostGIS, cruzamentos de telemetria, eventos sem duplicar, `sp_macro_mapa_*`). `tests/sql/04_motor_jornada.sql` cobre V1–V11: 4/4 ok. **Falta:** códigos de macro da Autotrac (Flávio), ligar o job à ingestão no n8n, tela de Jornada (spec `jornada-painel.md`), parâmetros por operação quando houver operações.

- **20/11/2026 (Marco 1):** documento do Marco 1 em `docs/marco1.html`, publicado em https://claude.ai/artifact/VbhvYjqVCWXXGqm2WpTbE6 (privado; compartilhar com o Michael pelo menu Share). Mensagens de cobrança para Flávio, Rafael, Natanael e André entregues ao Marcus no chat. Falta preencher no BoM: titular da conta Hostinger e valores.

- **20/11/2026 (Admin · Usuários e login real, local):** login real (`acesso.sp_login_*`, `sp_sessao_criar`, `sp_autorizar`, `sp_auth_me`, `sp_logout`) e Admin · Usuários (`sp_usuario_*`, `sp_definicao_*`, `sp_senha_definir`, `sp_sessao_*`) no banco; workflows `sub-autorizar`, `api-auth` (health, login, me, logout, senha/link, senha/definir) e `api-admin` no n8n local; Caddy local na porta 8088 (cookies); front com a tela Usuários e perfis e criar senha pelo link. Testes: 3 SQL ok, `tests/rotas/admin-usuarios.sh` 22/22 (`ADMIN_EMAIL=... ADMIN_SENHA=... sh tests/rotas/admin-usuarios.sh`), 12 do front, fluxo na tela a 1440 px. Admin local: `admin@mxmidas.com` (senha só com o Marcus). **Ambiente local:** `docker compose up -d postgres`, `docker compose --profile app up -d n8n`, `docker compose --profile app up -d --no-deps caddy`, front `npx ng serve --host 127.0.0.1 --port 4317 --proxy-config proxy.conf.json` (a 4300 está ocupada por outro app). **Pendente:** "esqueci a senha" (sem envio de e-mail: decidir), cadastro de operações, tela em 390 px, VPS.

- **20/11/2026 (front criado, dados fictícios):** `frontend/` Angular 21 com a base do Elysium (build, Dockerfile, nginx, proxy para o n8n em 5679). Clean por feature: `core/auth` (domínio, porta `AuthApi` com adaptador HTTP e fictício, sessão em signals, guardas, interceptor), `core/navegacao` (menu por permissão), `layout/shell`, `features/acesso` (login, esqueci, definir senha), `features/inicio` (domínio, `InicioApi`, store com consulta a cada 5 s, página), em construção e sem acesso. Trocar `USAR_DADOS_FICTICIOS` em `core/config.ts` quando a API existir. Login fictício: `<perfil>@exemplo.com` (operacao, diretoria, frotaopi, central, ti, admin) + senha `tic-demo-2026`. Build ok, 7 testes ok, conferido no navegador a 1440 px (login → início, menu por perfil, sem acesso). **Pendente:** spec `seguranca-acesso.md`; layout aprovado formalmente; API real `/api/auth/*` e `/api/inicio`; logo; telas Central, Jornada, OPI.

- **20/11/2026 (banco criado e testado localmente):** `docker-compose.yml` (postgres PostGIS 17, migrador, n8n/front/caddy no perfil `app`), `.env.example`, `scripts/migrar.sh` e `scripts/testar-sql.sh`. Migrations 001–007: 39 tabelas em 6 schemas, partições mensais em posição/evento/alarme (`controle.job_particoes`), auditoria só INSERT, EXCLUDE para conjunto/sessão/parâmetro sobrepostos, carga inicial (6 perfis, 17 permissões, FFRO 005 rev5 com 42 itens, 34 parâmetros do roteiro). Funções de domínio `fn_parametro`, `fn_parametro_num`, `fn_nivel_velocidade`, `fn_opi_resultado`. Teste `tests/sql/01_estrutura.sql`: ok. Banco local `tic` migrado. **Pendente:** nenhuma `sp_*` ainda (login, sessão, usuários); aplicar na VPS (SSH travado); operações oficiais; quem é avaliado por vídeo/sistema/humano na OPI (proposta).

- **20/11/2026 (estudo e plano):** lidos roteiro v1, 3 OPIs (FFRO 005 rev5 e FOPE 016 rev02), e-mail de violações 13/11 e os 5 painéis HTML (Jornada TIC, Jornada Ipiranga, Torre, Entregas OPASC e Araucária). Escritos `docs/roteiro-fase1.md`, `docs/estudo-paineis.md`, `docs/plano.md`, decisão 001 (proposta), índice de specs. **Não feito:** commit, GitHub, VPS. Achados principais: Torre e Ipiranga dependem do Datapar (fora do obrigatório); limites diferentes por operação; FFRO 005 não tem item 36 e tem itens de polaridade invertida; percentual da OPI precisa ser calculado.
