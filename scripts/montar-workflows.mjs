// Monta os JSON dos workflows do n8n a partir do código em n8n/codigo/. Não publica nada.
//   node scripts/montar-workflows.mjs
// Saída: n8n/workflows/*.json (ids estáveis em n8n/ids.json). Publicar: sh scripts/publicar-n8n.sh
// Arquitetura (decisão 002): o n8n é só adaptador. Cada rota: webhook → preparar → sub-autorizar → SELECT sp_* → responder.
import { randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const ler = (p) => readFileSync(join(raiz, p), 'utf8');
const arqIds = join(raiz, 'n8n/ids.json');
const ids = existsSync(arqIds) ? JSON.parse(readFileSync(arqIds, 'utf8')) : {};
const uid = (chave) => (ids[chave] ??= randomUUID());

const WF = { subAutorizar: 'TicSubAutorizar1', apiAuth: 'TicApiAuth000001', apiAdmin: 'TicApiAdmin00001', apiCentral: 'TicApiCentral001', apiJornada: 'TicApiJornada001' };
const PG = { postgres: { id: 'TicPostgresN8n01', name: 'Postgres TIC (n8n)' } };

const COMUM = ler('n8n/codigo/comum.js');
const SENHA = ler('n8n/codigo/senha.js');

/** Lê blocos "// @no Nome [senha]" de um arquivo de código. */
function blocos(arquivo) {
  const mapa = {};
  let atual = null;
  for (const l of ler(arquivo).split('\n')) {
    const m = l.match(/^\/\/ @no (.+?)(\s+\[senha\])?\s*$/);
    if (m) {
      atual = { nome: m[1], senha: Boolean(m[2]), linhas: [] };
      mapa[atual.nome] = atual;
    } else if (atual) atual.linhas.push(l);
  }
  return Object.fromEntries(
    Object.values(mapa).map((b) => [b.nome, [COMUM, b.senha ? SENHA : '', b.linhas.join('\n').trim()].filter(Boolean).join('\n\n')]),
  );
}

function novoWorkflow(id, nome) {
  const nodes = [];
  const connections = {};
  const w = {
    id, name: nome, nodes, connections, active: false, pinData: {},
    // Senha e token passam por aqui: execuções NÃO são guardadas.
    settings: { executionOrder: 'v1', saveDataSuccessExecution: 'none', saveDataErrorExecution: 'none',
      saveManualExecutions: false, saveExecutionProgress: false, callerPolicy: 'workflowsFromSameOwner' },
  };
  const no = (nome, tipo, versao, pos, parameters, extra = {}) => {
    nodes.push({ id: uid(`${id}:${nome}`), name: nome, type: tipo, typeVersion: versao, position: pos, parameters, ...extra });
    return nome;
  };
  const liga = (origem, ...saidas) => {
    connections[origem] = { main: saidas.map((s) => (s ? [].concat(s).map((d) => ({ node: d, type: 'main', index: 0 })) : [])) };
  };
  return { w, no, liga };
}

const code = (no, nome, pos, js) => no(nome, 'n8n-nodes-base.code', 2, pos, { jsCode: js });
// Postgres: parâmetros $1, $2... vindos de uma expressão que devolve lista. Erro do banco vai para a saída 1.
const sql = (no, nome, pos, query, params) =>
  no(nome, 'n8n-nodes-base.postgres', 2.6, pos,
    { operation: 'executeQuery', query, options: { queryReplacement: `={{ ${params} }}` } },
    { credentials: PG, executeOnce: true, onError: 'continueErrorOutput' });

// ---------------- sub-autorizar ----------------
{
  const { w, no, liga } = novoWorkflow(WF.subAutorizar, 'sub-autorizar');
  const c = blocos('n8n/codigo/sub-autorizar.js');
  no('Entrada', 'n8n-nodes-base.executeWorkflowTrigger', 1.1, [0, 0], { inputSource: 'passthrough' });
  code(no, 'Hashes', [220, 0], c['Hashes']);
  sql(no, 'Autorizar', [440, 0], 'SELECT * FROM acesso.sp_autorizar($1, $2, $3, $4)',
    '[$json.tokenHash, $json.csrfHash, $json.metodo, $json.permissao]');
  code(no, 'Resultado', [660, 0], c['Resultado']);
  liga('Entrada', ['Hashes']);
  liga('Hashes', ['Autorizar']);
  liga('Autorizar', ['Resultado'], ['Resultado']); // erro do banco = não autorizado
  salvar('sub-autorizar.json', w);
}

// ---------------- api-auth ----------------
{
  const { w, no, liga } = novoWorkflow(WF.apiAuth, 'api-auth');
  const c = blocos('n8n/codigo/auth/rotas.js');
  const webhook = (nome, metodo, caminho, pos) =>
    no(nome, 'n8n-nodes-base.webhook', 2, pos,
      { httpMethod: metodo, path: `api/${caminho}`, responseMode: 'responseNode', options: {} },
      { webhookId: uid(`webhook:${caminho}:${metodo}`) });
  const autorizar = (nome, pos) =>
    no(nome, 'n8n-nodes-base.executeWorkflow', 1.2, pos, {
      source: 'database',
      workflowId: { __rl: true, value: WF.subAutorizar, mode: 'id' },
      workflowInputs: { mappingMode: 'defineBelow', value: {}, matchingColumns: [], schema: [], attemptToConvertTypes: false, convertFieldsToString: true },
      options: { waitForSubWorkflow: true },
    });
  const seAutorizado = (nome, pos) =>
    no(nome, 'n8n-nodes-base.if', 2.2, pos, {
      conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 }, combinator: 'and',
        conditions: [{ id: uid(`cond:${nome}`), leftValue: '={{ $json.autorizado }}', rightValue: true,
          operator: { type: 'boolean', operation: 'true', singleValue: true } }] },
      options: {},
    });

  no('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1800, 600], {
    respondWith: 'json',
    responseBody: '={{ $json.body }}',
    options: {
      responseCode: '={{ $json.status }}',
      responseHeaders: { entries: [
        { name: 'Cache-Control', value: 'no-store' },
        // Dois cookies não cabem num cabeçalho só: o Caddy transforma estes em dois Set-Cookie (caddy/Caddyfile).
        { name: 'X-Tic-Cookie-1', value: "={{ $json.cookies[0] || '' }}" },
        { name: 'X-Tic-Cookie-2', value: "={{ $json.cookies[1] || '' }}" },
      ] },
    },
  });
  code(no, 'Erro seguro', [1580, 1200], c['Erro seguro']);
  liga('Erro seguro', ['Responder']);
  code(no, 'Negar', [1580, 1000], c['Negar']);
  liga('Negar', ['Responder']);

  // GET /api/health (anônima)
  webhook('GET health', 'GET', 'health', [0, 0]);
  code(no, 'Health', [220, 0], c['Health']);
  liga('GET health', ['Health']);
  liga('Health', ['Responder']);

  // POST /api/auth/login (anônima): buscar → conferir hash → criar sessão ou registrar falha
  webhook('POST auth/login', 'POST', 'auth/login', [0, 200]);
  code(no, 'Login preparar', [220, 200], c['Login preparar']);
  sql(no, 'Login buscar', [440, 200], 'SELECT * FROM acesso.sp_login_buscar($1)', '[$json.email]');
  code(no, 'Login conferir', [660, 200], c['Login conferir']);
  no('Login certo?', 'n8n-nodes-base.if', 2.2, [880, 200], {
    conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 }, combinator: 'and',
      conditions: [{ id: uid('cond:login'), leftValue: '={{ $json.acao }}', rightValue: 'sucesso', operator: { type: 'string', operation: 'equals' } }] },
    options: {},
  });
  sql(no, 'Sessao criar', [1100, 100], "SELECT * FROM acesso.sp_sessao_criar($1::uuid, $2, $3, NULLIF($4, '')::inet, $5)",
    "[$json.usuarioId, $json.tokenHash, $json.csrfHash, $('Login preparar').first().json.ip, $('Login preparar').first().json.userAgent]");
  sql(no, 'Login me', [1320, 100], 'SELECT * FROM acesso.sp_auth_me($1::uuid)', "[$('Login conferir').first().json.usuarioId]");
  code(no, 'Login resposta', [1540, 100], c['Login resposta']);
  sql(no, 'Login falha', [1100, 300], "SELECT * FROM acesso.sp_login_falha($1, NULLIF($2, '')::inet)",
    "[$('Login preparar').first().json.email, $('Login preparar').first().json.ip]");
  code(no, 'Login falha resposta', [1320, 300], c['Login falha resposta']);
  liga('POST auth/login', ['Login preparar']);
  liga('Login preparar', ['Login buscar']);
  liga('Login buscar', ['Login conferir'], ['Erro seguro']);
  liga('Login conferir', ['Login certo?']);
  liga('Login certo?', ['Sessao criar'], ['Login falha']);
  liga('Sessao criar', ['Login me'], ['Erro seguro']);
  liga('Login me', ['Login resposta'], ['Erro seguro']);
  liga('Login resposta', ['Responder']);
  liga('Login falha', ['Login falha resposta'], ['Erro seguro']);
  liga('Login falha resposta', ['Responder']);

  // GET /api/auth/me (sessão)
  webhook('GET auth/me', 'GET', 'auth/me', [0, 600]);
  code(no, 'Me entrada', [220, 600], c['Me entrada']);
  autorizar('Me autorizar', [440, 600]);
  seAutorizado('Me autorizado?', [660, 600]);
  sql(no, 'Me buscar', [880, 560], 'SELECT * FROM acesso.sp_auth_me($1::uuid)', '[$json.usuarioId]');
  code(no, 'Me resposta', [1100, 560], c['Me resposta']);
  liga('GET auth/me', ['Me entrada']);
  liga('Me entrada', ['Me autorizar']);
  liga('Me autorizar', ['Me autorizado?']);
  liga('Me autorizado?', ['Me buscar'], ['Negar']);
  liga('Me buscar', ['Me resposta'], ['Erro seguro']);
  liga('Me resposta', ['Responder']);

  // POST /api/auth/logout (sessão + CSRF)
  webhook('POST auth/logout', 'POST', 'auth/logout', [0, 800]);
  code(no, 'Logout entrada', [220, 800], c['Logout entrada']);
  autorizar('Logout autorizar', [440, 800]);
  seAutorizado('Logout autorizado?', [660, 800]);
  sql(no, 'Logout gravar', [880, 760], "SELECT * FROM acesso.sp_logout($1::uuid, NULLIF($2, '')::inet)", '[$json.sessaoId, $json.ip]');
  code(no, 'Logout resposta', [1100, 760], c['Logout resposta']);
  liga('POST auth/logout', ['Logout entrada']);
  liga('Logout entrada', ['Logout autorizar']);
  liga('Logout autorizar', ['Logout autorizado?']);
  liga('Logout autorizado?', ['Logout gravar'], ['Negar']);
  liga('Logout gravar', ['Logout resposta'], ['Erro seguro']);
  liga('Logout resposta', ['Responder']);

  // POST /api/auth/senha/link (anônima): o link ainda vale?
  webhook('POST auth/senha/link', 'POST', 'auth/senha/link', [0, 1000]);
  code(no, 'Link preparar', [220, 1000], c['Link preparar']);
  sql(no, 'Link validar', [440, 1000], 'SELECT * FROM acesso.sp_definicao_validar($1)', '[$json.tokenHash]');
  code(no, 'Link resposta', [660, 1000], c['Link resposta']);
  liga('POST auth/senha/link', ['Link preparar']);
  liga('Link preparar', ['Link validar']);
  liga('Link validar', ['Link resposta'], ['Erro seguro']);
  liga('Link resposta', ['Responder']);

  // POST /api/auth/senha/definir (anônima): valida link → política → grava hash → já entra
  webhook('POST auth/senha/definir', 'POST', 'auth/senha/definir', [0, 1200]);
  code(no, 'Definir preparar', [220, 1200], c['Definir preparar']);
  sql(no, 'Definir validar', [440, 1200], 'SELECT * FROM acesso.sp_definicao_validar($1)', '[$json.tokenHash]');
  code(no, 'Definir conferir', [660, 1200], c['Definir conferir']);
  no('Definir pode gravar?', 'n8n-nodes-base.if', 2.2, [880, 1200], {
    conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 }, combinator: 'and',
      conditions: [{ id: uid('cond:definir'), leftValue: '={{ $json.acao }}', rightValue: 'gravar', operator: { type: 'string', operation: 'equals' } }] },
    options: {},
  });
  sql(no, 'Definir gravar', [1100, 1160], "SELECT * FROM acesso.sp_senha_definir($1, $2, NULLIF($3, '')::inet)",
    "[$('Definir preparar').first().json.tokenHash, $json.senhaHash, $('Definir preparar').first().json.ip]");
  sql(no, 'Definir sessao', [1320, 1160], "SELECT * FROM acesso.sp_sessao_criar($1::uuid, $2, $3, NULLIF($4, '')::inet, $5)",
    "[$json.usuario_id, $('Definir conferir').first().json.tokenHash, $('Definir conferir').first().json.csrfHash, $('Definir preparar').first().json.ip, $('Definir preparar').first().json.userAgent]");
  sql(no, 'Definir me', [1540, 1160], 'SELECT * FROM acesso.sp_auth_me($1::uuid)', "[$('Definir gravar').first().json.usuario_id]");
  code(no, 'Definir resposta', [1760, 1160], c['Definir resposta']);
  code(no, 'Definir recusa', [1100, 1300], c['Definir recusa']);
  liga('POST auth/senha/definir', ['Definir preparar']);
  liga('Definir preparar', ['Definir validar']);
  liga('Definir validar', ['Definir conferir'], ['Erro seguro']);
  liga('Definir conferir', ['Definir pode gravar?']);
  liga('Definir pode gravar?', ['Definir gravar'], ['Definir recusa']);
  liga('Definir gravar', ['Definir sessao'], ['Erro seguro']);
  liga('Definir sessao', ['Definir me'], ['Erro seguro']);
  liga('Definir me', ['Definir resposta'], ['Erro seguro']);
  liga('Definir resposta', ['Responder']);
  liga('Definir recusa', ['Responder']);

  salvar('api-auth.json', w);
}

// ---------------- api-admin (spec admin-usuarios) ----------------
// Ids vão em ?id= ou no corpo, nunca no caminho (webhook com :param no n8n sai do padrão /api/...).
{
  const { w, no, liga } = novoWorkflow(WF.apiAdmin, 'api-admin');
  const c = blocos('n8n/codigo/admin/rotas.js');
  const webhook = (nome, metodo, caminho, pos) =>
    no(nome, 'n8n-nodes-base.webhook', 2, pos,
      { httpMethod: metodo, path: `api/${caminho}`, responseMode: 'responseNode', options: {} },
      { webhookId: uid(`webhook:${caminho}:${metodo}`) });
  const entrada = (nome, metodo, pos) => code(no, nome, pos,
    `${COMUM}\n\nconst req = lerRequisicao($input.first().json, '${metodo}');\nreturn [{ json: { ...req, host: undefined, permissao: 'usuario.gerir' } }];`);
  const autorizar = (nome, pos) =>
    no(nome, 'n8n-nodes-base.executeWorkflow', 1.2, pos, {
      source: 'database',
      workflowId: { __rl: true, value: WF.subAutorizar, mode: 'id' },
      workflowInputs: { mappingMode: 'defineBelow', value: {}, matchingColumns: [], schema: [], attemptToConvertTypes: false, convertFieldsToString: true },
      options: { waitForSubWorkflow: true },
    });
  const seAutorizado = (nome, pos) =>
    no(nome, 'n8n-nodes-base.if', 2.2, pos, {
      conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 }, combinator: 'and',
        conditions: [{ id: uid(`cond:${nome}`), leftValue: '={{ $json.autorizado }}', rightValue: true,
          operator: { type: 'boolean', operation: 'true', singleValue: true } }] },
      options: {},
    });

  no('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1800, 600], {
    respondWith: 'json',
    responseBody: '={{ $json.body }}',
    options: { responseCode: '={{ $json.status }}', responseHeaders: { entries: [
      { name: 'Cache-Control', value: 'no-store' },
      { name: 'X-Tic-Cookie-1', value: "={{ $json.cookies[0] || '' }}" },
      { name: 'X-Tic-Cookie-2', value: "={{ $json.cookies[1] || '' }}" },
    ] } },
  });
  code(no, 'Erro seguro', [1580, 1700], c['Erro seguro']);
  liga('Erro seguro', ['Responder']);
  code(no, 'Negar', [1580, 1500], c['Negar']);
  liga('Negar', ['Responder']);

  /** Webhook → entrada → sub-autorizar → se ok: [preparo] → SQL → resposta; senão Negar. */
  const rota = (r, y) => {
    webhook(r.webhook, r.metodo, r.caminho, [0, y]);
    entrada(`${r.base} entrada`, r.metodo, [200, y]);
    autorizar(`${r.base} autorizar`, [400, y]);
    seAutorizado(`${r.base} autorizado?`, [600, y]);
    const sqlNome = `${r.base} banco`;
    let depoisDoIf = sqlNome;
    if (r.preparo) {
      code(no, r.preparo, [800, y - 40], c[r.preparo]);
      liga(r.preparo, [sqlNome]);
      depoisDoIf = r.preparo;
    }
    sql(no, sqlNome, [1000, y - 40], r.query, r.params);
    code(no, `${r.base} resposta`, [1200, y - 40], c[`${r.base} resposta`]);
    liga(r.webhook, [`${r.base} entrada`]);
    liga(`${r.base} entrada`, [`${r.base} autorizar`]);
    liga(`${r.base} autorizar`, [`${r.base} autorizado?`]);
    liga(`${r.base} autorizado?`, [depoisDoIf], ['Negar']);
    liga(sqlNome, [`${r.base} resposta`], ['Erro seguro']);
    liga(`${r.base} resposta`, ['Responder']);
  };
  const A = (base) => `$('${base} autorizar').first().json`;
  const E = (base) => `$('${base} entrada').first().json`;

  rota({ webhook: 'GET admin/usuarios', metodo: 'GET', caminho: 'admin/usuarios', base: 'Listar',
    query: 'SELECT * FROM acesso.sp_usuario_listar($1::uuid)', params: `[${A('Listar')}.usuarioId]` }, 0);
  rota({ webhook: 'GET admin/perfis', metodo: 'GET', caminho: 'admin/perfis', base: 'Perfis',
    query: 'SELECT * FROM acesso.sp_perfil_listar($1::uuid)', params: `[${A('Perfis')}.usuarioId]` }, 200);
  rota({ webhook: 'POST admin/usuarios', metodo: 'POST', caminho: 'admin/usuarios', base: 'Criar', preparo: 'Criar preparar',
    query: "SELECT * FROM acesso.sp_usuario_criar($1::uuid, $2, $3, $4, $5::boolean, $6::uuid[], NULLIF($7, '')::inet)",
    params: `[${A('Criar')}.usuarioId, $json.nome, $json.email, $json.perfil, $json.todas, '{' + $json.operacoes.join(',') + '}', ${A('Criar')}.ip]` }, 400);
  rota({ webhook: 'PATCH admin/usuarios', metodo: 'PATCH', caminho: 'admin/usuarios', base: 'Atualizar', preparo: 'Atualizar preparar',
    query: "SELECT * FROM acesso.sp_usuario_atualizar($1::uuid, $2::uuid, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''), NULLIF($6, '')::boolean, NULLIF($7, '')::boolean, NULLIF($8, '')::uuid[], NULLIF($9, '')::inet)",
    params: `[${A('Atualizar')}.usuarioId, $json.alvo, $json.nome ?? '', $json.email ?? '', $json.perfil ?? '', $json.ativo === null ? '' : String($json.ativo), $json.todas === null ? '' : String($json.todas), $json.operacoes === null ? '' : '{' + $json.operacoes.join(',') + '}', ${A('Atualizar')}.ip]` }, 600);
  rota({ webhook: 'POST admin/usuarios/link-senha', metodo: 'POST', caminho: 'admin/usuarios/link-senha', base: 'Link', preparo: 'Link gerar',
    query: "SELECT * FROM acesso.sp_definicao_criar($1::uuid, $2::uuid, $3, NULLIF($4, '')::inet)",
    params: `[${A('Link')}.usuarioId, $json.alvo, $json.tokenHash, ${A('Link')}.ip]` }, 800);
  rota({ webhook: 'GET admin/sessoes', metodo: 'GET', caminho: 'admin/sessoes', base: 'Sessoes',
    query: 'SELECT * FROM acesso.sp_sessao_listar($1::uuid, $2::uuid)',
    params: `[${A('Sessoes')}.usuarioId, String(${E('Sessoes')}.query.usuario || '').slice(0, 36)]` }, 1000);
  rota({ webhook: 'DELETE admin/sessoes', metodo: 'DELETE', caminho: 'admin/sessoes', base: 'Revogar',
    query: "SELECT * FROM acesso.sp_sessao_revogar($1::uuid, $2::uuid, NULLIF($3, '')::inet)",
    params: `[${A('Revogar')}.usuarioId, String(${E('Revogar')}.query.id || '').slice(0, 36), ${A('Revogar')}.ip]` }, 1200);
  rota({ webhook: 'POST admin/usuarios/encerrar-sessoes', metodo: 'POST', caminho: 'admin/usuarios/encerrar-sessoes', base: 'Revogar todas',
    query: "SELECT * FROM acesso.sp_sessao_revogar_todas($1::uuid, $2::uuid, NULLIF($3, '')::inet)",
    params: `[${A('Revogar todas')}.usuarioId, String((${E('Revogar todas')}.body || {}).id || '').slice(0, 36), ${A('Revogar todas')}.ip]` }, 1400);

  salvar('api-admin.json', w);
}

// ---------------- APIs de tela (mesmo molde: webhook → entrada com a permissão → sub-autorizar → SQL → resposta) ----------------
function apiDeTela(wfId, nomeWf, arquivoCodigo, montarRotas) {
  const { w, no, liga } = novoWorkflow(wfId, nomeWf);
  const c = blocos(arquivoCodigo);
  no('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1800, 600], {
    respondWith: 'json',
    responseBody: '={{ $json.body }}',
    options: { responseCode: '={{ $json.status }}', responseHeaders: { entries: [
      { name: 'Cache-Control', value: 'no-store' },
      { name: 'X-Tic-Cookie-1', value: "={{ $json.cookies[0] || '' }}" },
      { name: 'X-Tic-Cookie-2', value: "={{ $json.cookies[1] || '' }}" },
    ] } },
  });
  code(no, 'Erro seguro', [1580, 1900], c['Erro seguro']);
  liga('Erro seguro', ['Responder']);
  code(no, 'Negar', [1580, 1700], c['Negar']);
  liga('Negar', ['Responder']);

  /** Webhook → entrada (com a permissão da rota) → sub-autorizar → SQL → resposta; senão Negar. */
  const rota = (r, y) => {
    const base = r.base;
    no(r.webhook, 'n8n-nodes-base.webhook', 2, [0, y],
      { httpMethod: r.metodo, path: `api/${r.caminho}`, responseMode: 'responseNode', options: {} },
      { webhookId: uid(`webhook:${r.caminho}:${r.metodo}`) });
    code(no, `${base} entrada`, [200, y],
      `${COMUM}\n\nconst req = lerRequisicao($input.first().json, '${r.metodo}');\nreturn [{ json: { ...req, permissao: '${r.permissao}' } }];`);
    no(`${base} autorizar`, 'n8n-nodes-base.executeWorkflow', 1.2, [400, y], {
      source: 'database',
      workflowId: { __rl: true, value: WF.subAutorizar, mode: 'id' },
      workflowInputs: { mappingMode: 'defineBelow', value: {}, matchingColumns: [], schema: [], attemptToConvertTypes: false, convertFieldsToString: true },
      options: { waitForSubWorkflow: true },
    });
    no(`${base} autorizado?`, 'n8n-nodes-base.if', 2.2, [600, y], {
      conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 }, combinator: 'and',
        conditions: [{ id: uid(`cond:central:${base}`), leftValue: '={{ $json.autorizado }}', rightValue: true,
          operator: { type: 'boolean', operation: 'true', singleValue: true } }] },
      options: {},
    });
    sql(no, `${base} banco`, [850, y - 40], r.query, r.params);
    code(no, `${base} resposta`, [1100, y - 40], c[r.resposta]);
    liga(r.webhook, [`${base} entrada`]);
    liga(`${base} entrada`, [`${base} autorizar`]);
    liga(`${base} autorizar`, [`${base} autorizado?`]);
    liga(`${base} autorizado?`, [`${base} banco`], ['Negar']);
    liga(`${base} banco`, [`${base} resposta`], ['Erro seguro']);
    liga(`${base} resposta`, ['Responder']);
  };
  const A = (b) => `$('${b} autorizar').first().json`;
  const Q = (b, campo, max) => `String((($('${b} entrada').first().json.query || {}).${campo}) || '').slice(0, ${max})`;
  const B = (b, campo, max) => `String((($('${b} entrada').first().json.body || {}).${campo}) || '').slice(0, ${max})`;
  montarRotas({ rota, A, Q, B });
  salvar(`${nomeWf}.json`, w);
}

// ---------------- api-central (spec central-alertas) ----------------
apiDeTela(WF.apiCentral, 'api-central', 'n8n/codigo/central/rotas.js', ({ rota, A, Q, B }) => {
  rota({ webhook: 'GET central/alertas', metodo: 'GET', caminho: 'central/alertas', base: 'Listar', permissao: 'alerta.ver', resposta: 'Listar resposta',
    query: "SELECT * FROM derivado.sp_central_listar($1::uuid, NULLIF($2, ''), NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''))",
    params: `[${A('Listar')}.usuarioId, ${Q('Listar', 'aba', 20)}, ${Q('Listar', 'nivel', 20)}, ${Q('Listar', 'tipo', 40)}, ${Q('Listar', 'q', 60)}]` }, 0);
  rota({ webhook: 'GET central/resumo', metodo: 'GET', caminho: 'central/resumo', base: 'Resumo', permissao: 'alerta.ver', resposta: 'Resumo resposta',
    query: 'SELECT * FROM derivado.sp_central_resumo($1::uuid)', params: `[${A('Resumo')}.usuarioId]` }, 200);
  rota({ webhook: 'GET central/alerta', metodo: 'GET', caminho: 'central/alerta', base: 'Detalhe', permissao: 'alerta.ver', resposta: 'Detalhe resposta',
    query: "SELECT * FROM derivado.sp_alerta_detalhe($1::uuid, $2::uuid, NULLIF($3, '')::inet)",
    params: `[${A('Detalhe')}.usuarioId, ${Q('Detalhe', 'id', 36)}, ${A('Detalhe')}.ip]` }, 400);
  rota({ webhook: 'POST central/alerta/assumir', metodo: 'POST', caminho: 'central/alerta/assumir', base: 'Assumir', permissao: 'alerta.tratar', resposta: 'Acao resposta',
    query: "SELECT * FROM derivado.sp_alerta_pegar($1::uuid, $2::uuid, NULLIF($3, '')::inet)",
    params: `[${A('Assumir')}.usuarioId, ${B('Assumir', 'id', 36)}, ${A('Assumir')}.ip]` }, 600);
  rota({ webhook: 'POST central/alerta/confirmar', metodo: 'POST', caminho: 'central/alerta/confirmar', base: 'Confirmar', permissao: 'alerta.tratar', resposta: 'Acao resposta',
    query: "SELECT * FROM derivado.sp_alerta_confirmar($1::uuid, $2::uuid, NULLIF($3, ''), NULLIF($4, '')::inet)",
    params: `[${A('Confirmar')}.usuarioId, ${B('Confirmar', 'id', 36)}, ${B('Confirmar', 'observacao', 1000)}, ${A('Confirmar')}.ip]` }, 800);
  rota({ webhook: 'POST central/alerta/falso', metodo: 'POST', caminho: 'central/alerta/falso', base: 'Falso', permissao: 'alerta.tratar', resposta: 'Acao resposta',
    query: "SELECT * FROM derivado.sp_alerta_falso($1::uuid, $2::uuid, $3, NULLIF($4, ''), NULLIF($5, '')::inet)",
    params: `[${A('Falso')}.usuarioId, ${B('Falso', 'id', 36)}, ${B('Falso', 'motivo', 30)}, ${B('Falso', 'observacao', 1000)}, ${A('Falso')}.ip]` }, 1000);
  rota({ webhook: 'POST central/alerta/mensagem', metodo: 'POST', caminho: 'central/alerta/mensagem', base: 'Mensagem', permissao: 'alerta.acionar', resposta: 'Acao resposta',
    query: "SELECT * FROM derivado.sp_alerta_mensagem($1::uuid, $2::uuid, $3, NULLIF($4, '')::inet)",
    params: `[${A('Mensagem')}.usuarioId, ${B('Mensagem', 'id', 36)}, ${B('Mensagem', 'texto', 400)}, ${A('Mensagem')}.ip]` }, 1200);
  rota({ webhook: 'POST central/alerta/sirene', metodo: 'POST', caminho: 'central/alerta/sirene', base: 'Sirene', permissao: 'alerta.acionar', resposta: 'Acao resposta',
    query: "SELECT * FROM derivado.sp_alerta_sirene($1::uuid, $2::uuid, NULLIF($3, '')::inet)",
    params: `[${A('Sirene')}.usuarioId, ${B('Sirene', 'id', 36)}, ${A('Sirene')}.ip]` }, 1400);
});

// ---------------- api-jornada (spec jornada-painel) ----------------
apiDeTela(WF.apiJornada, 'api-jornada', 'n8n/codigo/jornada/rotas.js', ({ rota, A, Q, B }) => {
  rota({ webhook: 'GET jornada/motoristas', metodo: 'GET', caminho: 'jornada/motoristas', base: 'Listar', permissao: 'jornada.ver', resposta: 'Listar resposta',
    query: "SELECT * FROM derivado.sp_jornada_listar($1::uuid, NULLIF($2, ''), NULLIF($3, ''), NULLIF($4, ''), $5::boolean)",
    params: `[${A('Listar')}.usuarioId, ${Q('Listar', 'faixa', 20)}, ${Q('Listar', 'dias', 10)}, ${Q('Listar', 'q', 60)}, ${Q('Listar', 'semcontrole', 5)} === 'true' ? 'true' : 'false']` }, 0);
  rota({ webhook: 'GET jornada/resumo', metodo: 'GET', caminho: 'jornada/resumo', base: 'Resumo', permissao: 'jornada.ver', resposta: 'Resumo resposta',
    query: 'SELECT * FROM derivado.sp_jornada_resumo($1::uuid)', params: `[${A('Resumo')}.usuarioId]` }, 200);
  rota({ webhook: 'GET jornada/motorista', metodo: 'GET', caminho: 'jornada/motorista', base: 'Detalhe', permissao: 'jornada.ver', resposta: 'Detalhe resposta',
    query: 'SELECT * FROM derivado.sp_jornada_detalhe($1::uuid, $2::uuid)', params: `[${A('Detalhe')}.usuarioId, ${Q('Detalhe', 'id', 36)}]` }, 400);
  rota({ webhook: 'POST jornada/tratativa', metodo: 'POST', caminho: 'jornada/tratativa', base: 'Tratativa', permissao: 'jornada.tratar', resposta: 'Tratativa resposta',
    query: "SELECT * FROM derivado.sp_tratativa_criar($1::uuid, $2::uuid, NULLIF($3, '')::uuid, $4, NULLIF($5, ''), NULLIF($6, '')::inet)",
    params: `[${A('Tratativa')}.usuarioId, ${B('Tratativa', 'motorista', 36)}, ${B('Tratativa', 'jornada', 36)}, ${B('Tratativa', 'tipo', 30)}, ${B('Tratativa', 'observacao', 1000)}, ${A('Tratativa')}.ip]` }, 600);
});

writeFileSync(arqIds, JSON.stringify(ids, null, 2) + '\n');

function salvar(arquivo, w) {
  const pasta = join(raiz, 'n8n/workflows');
  mkdirSync(pasta, { recursive: true });
  writeFileSync(join(pasta, arquivo), JSON.stringify(w, null, 2) + '\n');
  console.log(`montado: n8n/workflows/${arquivo} (${w.nodes.length} nós)`);
}
