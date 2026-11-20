// Nós Code do sub-workflow sub-autorizar: primeiro passo de toda rota com sessão.
// Entrada (item do chamador): tokenSessao, csrfCabecalho, metodo, permissao, ip, https.
// Saída: autorizado, http (200/401/403), codigo, usuarioId, sessaoId, perfil, ip, https. Nunca devolve o token.

// @no Hashes
const e = $input.first().json;
const hex = (v) => (v ? crypto.createHash('sha256').update(String(v)).digest('hex') : '');
return [{ json: {
  tokenHash: hex(e.tokenSessao),
  csrfHash: hex(e.csrfCabecalho),
  metodo: String(e.metodo || 'GET').toUpperCase(),
  permissao: String(e.permissao || ''),
} }];

// @no Resultado
const e = $('Entrada').first().json;
const r = linha($input.all());
const mapa = { ok: [200, null], sem_sessao: [401, 'SEM_SESSAO'], csrf: [403, 'CSRF'], proibido: [403, 'SEM_PERMISSAO'] };
const [http, codigo] = mapa[r.status] || [401, 'SEM_SESSAO'];
return [{ json: {
  autorizado: r.status === 'ok',
  http, codigo,
  usuarioId: r.usuario_id || null,
  sessaoId: r.sessao_id || null,
  perfil: r.perfil || null,
  ip: e.ip || '',
  https: e.https === true,
} }];
