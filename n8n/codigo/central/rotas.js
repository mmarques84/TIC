// Código dos nós Code do workflow api-central (spec central-alertas). Adaptador: só prepara e responde.
// Cada rota passa antes pelo sub-autorizar com a permissão da rota; o banco confere de novo.

// @no Listar resposta
return resposta(200, linha($input.all()).alertas || []);

// @no Resumo resposta
return resposta(200, linha($input.all()).resumo || {});

// @no Detalhe resposta
return resposta(200, linha($input.all()).alerta || {});

// @no Acao resposta
return resposta(200, linha($input.all()).alerta || {});

// @no Negar
const a = $input.first().json;
return resposta(a.http, { codigo: a.codigo }, a.http === 401 ? cookiesApagar({ https: a.https }) : []);

// @no Erro seguro
const bruto = $input.first().json || {};
const msg = [bruto.message, bruto.error && bruto.error.message, typeof bruto.error === 'string' ? bruto.error : ''].filter(Boolean).join(' ');
const codigos = { SEM_PERMISSAO: 403, NAO_ENCONTRADO: 404, ALERTA_JA_TRATADO: 409, MOTIVO_OBRIGATORIO: 400, TEXTO_INVALIDO: 400 };
const codigo = Object.keys(codigos).find((c) => msg.includes(c)) || (msg.includes('invalid input syntax for type uuid') ? 'NAO_ENCONTRADO' : null);
return resposta(codigo ? codigos[codigo] : 500, { codigo: codigo || 'ERRO' });
