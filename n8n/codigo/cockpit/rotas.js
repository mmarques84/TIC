// @no Resumo resposta
return resposta(200, linha($input.all()).resultado);

// @no Negar
const a = $input.first().json;
return resposta(a.http, { codigo: a.codigo }, a.http === 401 ? cookiesApagar({ https: a.https }) : []);

// @no Erro seguro
const erro = $input.first().json;
const mensagem = [erro.message, erro.error?.message, typeof erro.error === 'string' ? erro.error : ''].join(' ');
if (mensagem.includes('SEM_PERMISSAO')) return resposta(403, { codigo: 'SEM_PERMISSAO' });
if (mensagem.includes('TIPO_INVALIDO') || mensagem.includes('invalid input syntax for type uuid')) {
  return resposta(400, { codigo: 'TIPO_INVALIDO' });
}
return resposta(500, { codigo: 'ERRO' });
