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

const WF = { subAutorizar: 'TicSubAutorizar1', apiAuth: 'TicApiAuth000001' };
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

  salvar('api-auth.json', w);
}

writeFileSync(arqIds, JSON.stringify(ids, null, 2) + '\n');

function salvar(arquivo, w) {
  const pasta = join(raiz, 'n8n/workflows');
  mkdirSync(pasta, { recursive: true });
  writeFileSync(join(pasta, arquivo), JSON.stringify(w, null, 2) + '\n');
  console.log(`montado: n8n/workflows/${arquivo} (${w.nodes.length} nós)`);
}
