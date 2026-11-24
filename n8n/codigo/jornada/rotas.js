// Código dos nós Code do workflow api-jornada (spec jornada-painel). Adaptador: só prepara e responde.

// @no Listar resposta
return resposta(200, linha($input.all()).motoristas || []);

// @no Resumo resposta
return resposta(200, linha($input.all()).resumo || {});

// @no Detalhe resposta
return resposta(200, linha($input.all()).motorista || {});

// @no Tratativa resposta
return resposta(200, linha($input.all()).motorista || {});

// @no Negar
const a = $input.first().json;
return resposta(a.http, { codigo: a.codigo }, a.http === 401 ? cookiesApagar({ https: a.https }) : []);

// @no Erro seguro
const bruto = $input.first().json || {};
const msg = [bruto.message, bruto.error && bruto.error.message, typeof bruto.error === 'string' ? bruto.error : ''].filter(Boolean).join(' ');
const codigos = { SEM_PERMISSAO: 403, NAO_ENCONTRADO: 404, TIPO_INVALIDO: 400, OBSERVACAO_OBRIGATORIA: 400 };
const codigo = Object.keys(codigos).find((c) => msg.includes(c)) || (msg.includes('invalid input syntax for type uuid') ? 'NAO_ENCONTRADO' : null);
return resposta(codigo ? codigos[codigo] : 500, { codigo: codigo || 'ERRO' });
