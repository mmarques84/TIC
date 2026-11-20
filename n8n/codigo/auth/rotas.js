// Código dos nós Code do workflow api-auth. Cada bloco "// @no <Nome do nó>" vira um nó;
// o montador cola comum.js (e senha.js quando marcado [senha]) antes de cada bloco.
// Regras: docs/specs/seguranca-acesso.md. Nada aqui grava no banco: só prepara e responde.

// @no Health
return resposta(200, { ok: true });

// @no Login preparar
const req = lerRequisicao($input.first().json, 'POST');
return [{ json: {
  email: texto(req.body.email, 254).trim().toLowerCase(),
  senha: texto(req.body.senha, 1024),
  ip: req.ip,
  userAgent: req.userAgent,
  https: req.https,
} }];

// @no Login conferir  [senha]
// Sempre confere um hash (o real ou o fictício): o tempo é o mesmo exista ou não o e-mail (R3).
const p = $('Login preparar').first().json;
const row = linha($input.all());
const confere = conferirSenha(p.senha, row.senha_hash);
if (!confere || !row.usuario_id || row.bloqueado === true) return [{ json: { acao: 'falha' } }];
const token = tokenNovo();
const csrf = tokenNovo();
return [{ json: { acao: 'sucesso', usuarioId: row.usuario_id, token, csrf, tokenHash: sha256(token), csrfHash: sha256(csrf) } }];

// @no Login resposta
const p = $('Login preparar').first().json;
const c = $('Login conferir').first().json;
const me = linha($input.all());
return resposta(200, me.usuario, cookiesSessao({ https: p.https }, c.token, c.csrf));

// @no Login falha resposta
// R3: mesma resposta para senha errada, e-mail inexistente, inativo ou bloqueado.
return resposta(401, { codigo: 'CREDENCIAIS_INVALIDAS' });

// @no Me entrada
const req = lerRequisicao($input.first().json, 'GET');
return [{ json: { ...req, body: undefined, permissao: '' } }];

// @no Me resposta
const row = linha($input.all());
if (!row.usuario) return resposta(401, { codigo: 'SEM_SESSAO' });
return resposta(200, row.usuario);

// @no Logout entrada
const req = lerRequisicao($input.first().json, 'POST');
return [{ json: { ...req, body: undefined, permissao: '' } }];

// @no Logout resposta
const a = $('Logout autorizar').first().json;
return resposta(200, { ok: true }, cookiesApagar({ https: a.https }));

// @no Negar
// 401 apaga os cookies; 403 (CSRF ou permissão) não mexe neles.
const a = $input.first().json;
return resposta(a.http, { codigo: a.codigo }, a.http === 401 ? cookiesApagar({ https: a.https }) : []);

// @no Erro seguro
// Erro do banco vira resposta curta com o código do RAISE; nada de mensagem interna para fora.
const bruto = $input.first().json || {};
const msg = [bruto.message, bruto.error && bruto.error.message, typeof bruto.error === 'string' ? bruto.error : ''].filter(Boolean).join(' ');
const codigos = { SEM_PERMISSAO: 403, USUARIO_INATIVO: 401, PARAMETRO_AUSENTE: 500 };
const codigo = Object.keys(codigos).find((c) => msg.includes(c));
if (codigo === 'USUARIO_INATIVO') return resposta(401, { codigo: 'CREDENCIAIS_INVALIDAS' });
return resposta(codigo ? codigos[codigo] : 500, { codigo: codigo || 'ERRO' });
