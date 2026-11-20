// ---- comum.js (colado no início de todo nó Code de rota; montado por scripts/montar-workflows.mjs) ----
// Adaptador de entrada (decisão 002): lê a requisição, prepara e responde. Nenhuma regra de negócio aqui.
// Nunca registra corpo, senha ou token.
const crypto = require('crypto');

function decodificar(v) {
  try { return decodeURIComponent(v); } catch { return ''; }
}

function lerRequisicao(item, metodo) {
  const h = item.headers || {};
  const cookies = {};
  for (const parte of String(h.cookie || '').split(';')) {
    const i = parte.indexOf('=');
    if (i > 0) cookies[parte.slice(0, i).trim()] = decodificar(parte.slice(i + 1).trim());
  }
  // O Caddy define X-Forwarded-Proto e X-Forwarded-For.
  const https = String(h['x-forwarded-proto'] || '').split(',')[0].trim() === 'https';
  const ip = String(h['x-forwarded-for'] || '').split(',')[0].trim().slice(0, 45) || '';
  return {
    https,
    ip,
    userAgent: String(h['user-agent'] || '').slice(0, 300),
    metodo,
    tokenSessao: cookies[nomeCookieSessao(https)] || '',
    csrfCabecalho: String(h['x-xsrf-token'] || ''),
    body: item.body && typeof item.body === 'object' ? item.body : {},
    query: item.query || {},
  };
}

// Produção (HTTPS): __Host-tic com Secure. Desenvolvimento (http): tic-dev.
function nomeCookieSessao(https) {
  return https ? '__Host-tic' : 'tic-dev';
}

const sha256 = (v) => crypto.createHash('sha256').update(String(v)).digest('hex');
const tokenNovo = () => crypto.randomBytes(32).toString('base64url');

function cookie(nome, valor, { https, httpOnly, maxAge }) {
  const partes = [`${nome}=${valor}`, 'Path=/', 'SameSite=Lax'];
  if (maxAge !== undefined) partes.push(`Max-Age=${maxAge}`);
  if (https) partes.push('Secure');
  if (httpOnly) partes.push('HttpOnly');
  return partes.join('; ');
}

/** Cookies de uma sessão nova: sessão (HttpOnly) + XSRF-TOKEN (o Angular lê e devolve no cabeçalho). */
function cookiesSessao(req, token, csrf) {
  return [
    cookie(nomeCookieSessao(req.https), token, { https: req.https, httpOnly: true }),
    cookie('XSRF-TOKEN', csrf, { https: req.https, httpOnly: false }),
  ];
}

function cookiesApagar(req) {
  return [
    cookie(nomeCookieSessao(req.https), '', { https: req.https, httpOnly: true, maxAge: 0 }),
    cookie('XSRF-TOKEN', '', { https: req.https, httpOnly: false, maxAge: 0 }),
  ];
}

/** Item que o nó "Responder" devolve: status HTTP, corpo JSON e até dois cookies. */
function resposta(status, body, cookies = []) {
  return [{ json: { status, body: body ?? {}, cookies } }];
}

const texto = (v, max) => (typeof v === 'string' && v.length <= max ? v : '');

// Nó Postgres: cada linha do resultado é um item. As funções sp_* devolvem sempre uma linha.
const linha = (itens) => (itens && itens[0] && itens[0].json) || {};
// ---- fim comum.js ----
