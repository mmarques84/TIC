// Código dos nós Code do workflow api-admin (spec admin-usuarios). Adaptador: só prepara e responde.
// Toda rota passa antes pelo sub-autorizar com a permissão usuario.gerir (o banco confere de novo).

// @no Listar resposta
return resposta(200, linha($input.all()).usuarios || []);

// @no Perfis resposta
return resposta(200, linha($input.all()).perfis || []);

// @no Criar preparar
const b = $('Criar entrada').first().json.body || {};
return [{ json: {
  nome: texto(b.nome, 120), email: texto(b.email, 254), perfil: texto(b.perfil, 30),
  todas: b.todasOperacoes !== false,
  operacoes: Array.isArray(b.operacoes) ? b.operacoes.filter((x) => typeof x === 'string').slice(0, 50) : [],
} }];

// @no Criar resposta
return resposta(201, linha($input.all()).usuario);

// @no Atualizar preparar
const e = $('Atualizar entrada').first().json;
const b = e.body || {};
const opc = (v, max) => (typeof v === 'string' && v.length <= max ? v : null);
return [{ json: {
  alvo: String(e.query.id || '').slice(0, 36),
  nome: opc(b.nome, 120), email: opc(b.email, 254), perfil: opc(b.perfil, 30),
  ativo: typeof b.ativo === 'boolean' ? b.ativo : null,
  todas: typeof b.todasOperacoes === 'boolean' ? b.todasOperacoes : null,
  operacoes: Array.isArray(b.operacoes) ? b.operacoes.filter((x) => typeof x === 'string').slice(0, 50) : null,
} }];

// @no Atualizar resposta
const r = linha($input.all());
return resposta(200, { ...r.usuario, sessoesEncerradas: r.sessoes_encerradas });

// @no Link gerar
// O token sai daqui uma única vez, na resposta. O banco guarda só o hash. Execuções do n8n não são salvas.
const b = $('Link entrada').first().json.body || {};
const token = tokenNovo();
return [{ json: { alvo: String(b.id || '').slice(0, 36), token, tokenHash: sha256(token) } }];

// @no Link resposta
const e = $('Link entrada').first().json;
const g = $('Link gerar').first().json;
const r = linha($input.all());
const origem = e.origem;
return resposta(200, { link: `${origem}/definir-senha?token=${g.token}`, expiraEm: r.expira_em, tipo: r.tipo });

// @no Sessoes resposta
return resposta(200, linha($input.all()).sessoes || []);

// @no Revogar resposta
return resposta(200, { ok: true });

// @no Revogar todas resposta
return resposta(200, { encerradas: linha($input.all()).encerradas });

// @no Negar
const a = $input.first().json;
return resposta(a.http, { codigo: a.codigo }, a.http === 401 ? cookiesApagar({ https: a.https }) : []);

// @no Erro seguro
const bruto = $input.first().json || {};
const msg = [bruto.message, bruto.error && bruto.error.message, typeof bruto.error === 'string' ? bruto.error : ''].filter(Boolean).join(' ');
const codigos = {
  SEM_PERMISSAO: 403, NAO_ENCONTRADO: 404, NOME_OBRIGATORIO: 400, EMAIL_INVALIDO: 400, PERFIL_INVALIDO: 400,
  EMAIL_JA_CADASTRADO: 409, USUARIO_INATIVO: 409, ULTIMO_ADMIN: 409, PROPRIO_USUARIO: 409,
  OPERACAO_OBRIGATORIA: 400, OPERACAO_INVALIDA: 400,
};
const codigo = Object.keys(codigos).find((c) => msg.includes(c)) || (msg.includes('invalid input syntax for type uuid') ? 'NAO_ENCONTRADO' : null);
return resposta(codigo ? codigos[codigo] : 500, { codigo: codigo || 'ERRO' });
