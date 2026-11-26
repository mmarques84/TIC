#!/usr/bin/env node
// Teste de conexão com as APIs da Autotrac (só leitura, só GET): API ATIC e API de Telemetria.
//
// Sem variáveis: usa o SANDBOX da ATIC (dados fictícios, aceita qualquer usuário).
// Produção: defina as variáveis no terminal (NUNCA no git, nunca no chat):
//   ATIC_URL      https://aapi3.autotrac-online.com.br/aticapi       (API ATIC)
//                 https://aapi4.autotrac-online.com.br/telemetryapi  (API de Telemetria)
//   ATIC_CHAVE    chave de acesso (cabeçalho Ocp-Apim-Subscription-Key), quando a API pedir
//   ATIC_USUARIO  usuário do Supervisor com permissão de acesso à API
//   ATIC_SENHA    senha desse usuário
// Atenção: produção só responde do IP de saída cadastrado no Home Office da Autotrac.
//
// O script mostra só status HTTP, quantidades e os nomes dos campos: nada de nome, CPF ou placa na tela.

// Com o argumento "telemetria" ou "atic", lê as credenciais AUTOTRAC_* do .env do projeto (fora do git).
const qual = (process.argv[2] || '').toLowerCase();
if (qual === 'telemetria' || qual === 'atic') {
  const fs = await import('node:fs');
  const arq = new URL('../.env', import.meta.url);
  const env = Object.fromEntries(
    fs.readFileSync(arq, 'utf8').split(/\r?\n/)
      .filter((l) => /^AUTOTRAC_[A-Z_]+=/.test(l))
      .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]),
  );
  process.env.ATIC_URL = qual === 'atic' ? env.AUTOTRAC_ATIC_URL : env.AUTOTRAC_TELEMETRIA_URL;
  process.env.ATIC_CHAVE = env.AUTOTRAC_CHAVE || '';
  process.env.ATIC_USUARIO = env.AUTOTRAC_USUARIO || '';
  process.env.ATIC_SENHA = env.AUTOTRAC_SENHA || '';
}
const url = (process.env.ATIC_URL || 'https://wapi.autotrac-online.com.br/sandboxaticapi')
  .trim()
  .replace(/\/v1\/accounts\/?$/, '')
  .replace(/\/$/, '');
const producao = !url.includes('/sandbox');
const telemetria = /telemetryapi/i.test(url);
// trim: espaço digitado antes/depois do usuário quebra o login.
const usuario = (process.env.ATIC_USUARIO || 'sandbox').trim();
const senha = process.env.ATIC_SENHA || 'sandbox';
const chave = (process.env.ATIC_CHAVE || '').trim();
const semChave = process.env.ATIC_SEM_CHAVE === '1'; // testar sem o cabeçalho da chave

if (producao && (!process.env.ATIC_USUARIO || !process.env.ATIC_SENHA)) {
  console.error('Produção exige ATIC_USUARIO e ATIC_SENHA no ambiente (ATIC_CHAVE quando a API pedir).');
  process.exit(2);
}

// A Autotrac NÃO usa o Basic padrão (base64): espera "Basic usuário:senha" em texto puro.
// Com base64 a produção responde 400 (conferido em 25/11/2026 no Postman).
const cabecalhos = {
  Authorization: `Basic ${usuario}:${senha}`,
  Accept: 'application/json',
  ...(chave && !semChave ? { 'Ocp-Apim-Subscription-Key': chave } : {}),
};

async function get(caminho) {
  const inicio = Date.now();
  try {
    const r = await fetch(url + caminho, { headers: cabecalhos, signal: AbortSignal.timeout(30000) });
    const texto = await r.text();
    let corpo = null;
    try { corpo = JSON.parse(texto); } catch { /* resposta não-JSON */ }
    const pistas = ['www-authenticate', 'x-error', 'x-message']
      .map((h) => r.headers.get(h) && `${h}: ${r.headers.get(h)}`)
      .filter(Boolean)
      .join(' · ');
    const resumo = corpo != null ? JSON.stringify(corpo).slice(0, 300) : texto.slice(0, 300) || '(corpo vazio)';
    return { status: r.status, ms: Date.now() - inicio, corpo, resumo: resumo + (pistas ? ' · ' + pistas : '') };
  } catch (e) {
    return { status: 0, ms: Date.now() - inicio, corpo: null, resumo: String(e.message || e) };
  }
}

const lista = (c) => (Array.isArray(c) ? c : Array.isArray(c?.Data) ? c.Data : []);
const campos = (l) => (l[0] ? Object.keys(l[0]).join(', ') : '(vazio)');

function linha(nome, r) {
  const l = lista(r.corpo);
  const ok = r.status >= 200 && r.status < 300;
  console.log(`${ok ? 'OK  ' : 'ERRO'} ${nome.padEnd(34)} HTTP ${String(r.status).padEnd(3)} ${String(r.ms).padStart(5)} ms  ${l.length} registro(s)${r.corpo?.IsLastPage === false ? ' (há mais páginas)' : ''}`);
  console.log(ok ? `     campos: ${campos(l)}` : `     resposta: ${r.resumo}`);
  return l;
}

const isoZ = (d) => d.toISOString().replace(/\.\d{3}Z$/, '+00:00'); // ATIC
const isoT = (d) => d.toISOString().slice(0, 19);                  // Telemetria

console.log(`API ${telemetria ? 'de Telemetria' : 'ATIC'} · ${producao ? 'PRODUÇÃO' : 'SANDBOX (dados fictícios)'} · ${url}`);
console.log(`usuário com ${usuario.length} caracteres · chave ${chave && !semChave ? 'enviada' : 'não enviada'}\n`);

const contas = linha('contas (/v1/accounts)', await get('/v1/accounts'));
if (!contas.length) {
  console.log('\nSem contas. 401/403 = chave, usuário, permissão ou IP. 400 = formato do pedido (tente ATIC_SEM_CHAVE=1).');
  process.exit(1);
}
const conta = contas[0].Code;
console.log(`     ${contas.length} conta(s); usando a 1ª (código interno ${conta}).`);

const veiculos = linha('veículos da conta', await get(`/v1/accounts/${conta}/vehicles?_limit=100`));
const autorizados = linha('unidades autorizadas', await get(`/v1/accounts/${conta}/authorizedvehicles?_limit=100&_vehicleInAuthorizedListActive=true`));
const v = autorizados[0]?.VehicleCode ?? veiculos[0]?.Code;
if (v == null) {
  console.log('\nNenhum veículo para testar.');
  process.exit(0);
}

const ate = new Date();
if (telemetria) {
  const de = new Date(ate.getTime() - 24 * 3600 * 1000);
  const jan = `_dateTimeFrom=${isoT(de)}&_dateTimeTo=${isoT(ate)}&_limit=100`;
  console.log(`\nVeículo de teste: código interno ${v} · últimas 24 h (UTC)`);
  const ev = linha('eventos de telemetria', await get(`/v1/accounts/${conta}/vehicles/${v}/alltelemetryevents?${jan}`));
  const tipos = [...new Set(ev.map((e) => e.EventNumber ?? e.EventCode ?? e.Event))].filter((x) => x != null);
  if (tipos.length) console.log(`     tipos de evento vistos: ${tipos.join(', ')}`);
  linha('eventos ADAS / SDS (câmera)', await get(`/v1/accounts/${conta}/vehicles/${v}/safetydrivingevents?${jan}`));
  process.exit(0);
}

linha('motoristas (/v1/drivers)', await get('/v1/drivers?_limit=500'));
linha('status de jornada (/v1/driverstatus)', await get('/v1/driverstatus?_limit=500'));
// Últimas 2 horas, em UTC (a ATIC aceita até 72 h por chamada e guarda 7 dias).
const de = new Date(ate.getTime() - 2 * 3600 * 1000);
const janela = `_dateTimeFrom=${encodeURIComponent(isoZ(de))}&_dateTimeTo=${encodeURIComponent(isoZ(ate))}&_limit=500`;
console.log(`\nVeículo de teste: código interno ${v} · janela ${isoZ(de)} → ${isoZ(ate)}`);
linha('posições', await get(`/v1/accounts/${conta}/vehicles/${v}/positions?${janela}`));
const macros = linha('mensagens de retorno (macros)', await get(`/v1/accounts/${conta}/vehicles/${v}/returnmessages?${janela}`));
const nums = [...new Set(macros.map((m) => m.MacroNumber))].sort((a, b) => a - b);
if (nums.length) console.log(`     números de macro vistos: ${nums.join(', ')}`);
linha('login/logout de motorista', await get(`/v1/accounts/${conta}/vehicles/${v}/driverlogs?${janela}`));
linha('alertas expandidos (OBC)', await get(`/v1/accounts/${conta}/vehicles/${v}/expandedalerts?${janela}`));
