// Importa usuários de uma planilha CSV pelo próprio portal (mesmas regras da tela Admin · Usuários).
// Para cada linha: cria a pessoa (POST /api/admin/usuarios) e gera o link de senha (POST /api/admin/usuarios/link-senha).
// Saída: um CSV com nome, e-mail, situação e o link de cada pessoa, para enviar. Links valem 24 h e aparecem só aqui.
//
// Uso (do computador do dev ou apontando para a VPS):
//   ADMIN_EMAIL=... ADMIN_SENHA=... node scripts/importar-usuarios.mjs material-cliente/usuarios.csv
// Opções (variáveis de ambiente):
//   API=http://localhost:8088/api        endereço da API (na VPS: https://<dominio>/api)
//   PORTAL=http://127.0.0.1:4317         endereço que vai nos links (na VPS: https://<dominio>)
//   SAIDA=material-cliente/usuarios-links.csv
//   SIMULAR=1                            só confere a planilha, não cria nada
//
// Planilha: cabeçalho na 1ª linha, separador ; ou , — colunas: nome, email, perfil, operacao (operacao opcional).
// Perfil aceita o código ou o nome: diretoria, operacao/operação, frota_opi/frota/opi, central, ti, admin.
// A planilha e a saída têm dados pessoais: ficam em material-cliente/ (fora do git).
import { readFileSync, writeFileSync } from 'node:fs';

const arquivo = process.argv[2];
const API = (process.env.API ?? 'http://localhost:8088/api').replace(/\/$/, '');
const PORTAL = (process.env.PORTAL ?? 'http://127.0.0.1:4317').replace(/\/$/, '');
const SAIDA = process.env.SAIDA ?? 'material-cliente/usuarios-links.csv';
const SIMULAR = process.env.SIMULAR === '1';
if (!arquivo) sair('Informe a planilha: node scripts/importar-usuarios.mjs material-cliente/usuarios.csv');
if (!SIMULAR && (!process.env.ADMIN_EMAIL || !process.env.ADMIN_SENHA)) sair('Informe ADMIN_EMAIL e ADMIN_SENHA (admin do portal).');

const PERFIS = {
  diretoria: 'diretoria', operacao: 'operacao', frota_opi: 'frota_opi', frota: 'frota_opi', opi: 'frota_opi', 'frota/opi': 'frota_opi',
  central: 'central', ti: 'ti', admin: 'admin', administrador: 'admin',
};
const semAcento = (t) => String(t ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

// ---------- ler a planilha ----------
const texto = readFileSync(arquivo, 'utf8').replace(/^﻿/, '');
const linhas = texto.split(/\r?\n/).filter((l) => l.trim());
const sep = (linhas[0].match(/;/g) ?? []).length >= (linhas[0].match(/,/g) ?? []).length ? ';' : ',';
const partir = (l) => {
  const out = []; let atual = ''; let aspas = false;
  for (const c of l) {
    if (c === '"') aspas = !aspas;
    else if (c === sep && !aspas) { out.push(atual.trim()); atual = ''; }
    else atual += c;
  }
  out.push(atual.trim());
  return out;
};
const cab = partir(linhas[0]).map(semAcento);
const col = (nome) => cab.findIndex((c) => c === nome || c.startsWith(nome));
const iNome = col('nome'), iEmail = col('e-mail') >= 0 ? col('e-mail') : col('email'), iPerfil = col('perfil'), iOp = col('operac');
if (iNome < 0 || iEmail < 0 || iPerfil < 0) sair(`Cabeçalho precisa de nome, email e perfil. Encontrado: ${cab.join(' | ')}`);

const pessoas = linhas.slice(1).map((l, n) => {
  const c = partir(l);
  const perfilTexto = semAcento(c[iPerfil]);
  return {
    linha: n + 2,
    nome: (c[iNome] ?? '').trim(),
    email: (c[iEmail] ?? '').trim().toLowerCase(),
    perfil: PERFIS[perfilTexto] ?? PERFIS[perfilTexto.replace(/\s+/g, '_')] ?? null,
    perfilTexto: c[iPerfil] ?? '',
    operacao: iOp >= 0 ? (c[iOp] ?? '').trim() : '',
  };
});

// Conferência antes de criar qualquer coisa.
const problemas = [];
const vistos = new Set();
for (const p of pessoas) {
  if (p.nome.length < 2) problemas.push(`linha ${p.linha}: nome vazio`);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(p.email)) problemas.push(`linha ${p.linha}: e-mail inválido "${p.email}"`);
  if (!p.perfil) problemas.push(`linha ${p.linha}: perfil desconhecido "${p.perfilTexto}" (use diretoria, operacao, frota_opi, central, ti ou admin)`);
  if (vistos.has(p.email)) problemas.push(`linha ${p.linha}: e-mail repetido na planilha "${p.email}"`);
  vistos.add(p.email);
}
console.log(`Planilha: ${pessoas.length} pessoa(s), separador "${sep}".`);
const comOperacao = pessoas.filter((p) => p.operacao && semAcento(p.operacao) !== 'todas');
if (comOperacao.length) {
  console.log(`Aviso: ${comOperacao.length} pessoa(s) com operação específica. As operações ainda não estão cadastradas no portal:`);
  console.log('       por enquanto todas entram vendo "Todas"; ajuste na tela quando as operações existirem.');
}
if (problemas.length) {
  console.log('\nCorrija antes de importar:');
  problemas.forEach((x) => console.log('  - ' + x));
  process.exit(1);
}
if (SIMULAR) {
  console.log('\nSimulação ok: nada foi criado.');
  pessoas.forEach((p) => console.log(`  ${p.nome} <${p.email}> → ${p.perfil}`));
  process.exit(0);
}

// ---------- sessão do admin ----------
const cookies = new Map();
const guardarCookies = (r) => {
  for (const c of r.headers.getSetCookie?.() ?? []) {
    const [par] = c.split(';');
    const i = par.indexOf('=');
    const nome = par.slice(0, i), valor = par.slice(i + 1);
    if (valor) cookies.set(nome, valor); else cookies.delete(nome);
  }
};
const cabecalhos = () => ({
  'Content-Type': 'application/json',
  Origin: PORTAL,
  Cookie: [...cookies].map(([k, v]) => `${k}=${v}`).join('; '),
  'X-XSRF-TOKEN': cookies.get('XSRF-TOKEN') ?? '',
});
async function chamar(metodo, rota, corpo) {
  const r = await fetch(`${API}/${rota}`, { method: metodo, headers: cabecalhos(), body: corpo ? JSON.stringify(corpo) : undefined });
  guardarCookies(r);
  const json = await r.json().catch(() => ({}));
  return { status: r.status, json };
}

const login = await chamar('POST', 'auth/login', { email: process.env.ADMIN_EMAIL, senha: process.env.ADMIN_SENHA });
if (login.status !== 200) sair(`Login do admin falhou (${login.status} ${login.json.codigo ?? ''}).`);
if (login.json.perfil !== 'admin') sair('Este usuário não é admin.');

// ---------- criar e gerar links ----------
const MSG = { EMAIL_JA_CADASTRADO: 'já existia', EMAIL_INVALIDO: 'e-mail inválido', PERFIL_INVALIDO: 'perfil inválido', NOME_OBRIGATORIO: 'nome vazio' };
const resultado = [];
for (const p of pessoas) {
  const criar = await chamar('POST', 'admin/usuarios', { nome: p.nome, email: p.email, perfil: p.perfil, todasOperacoes: true, operacoes: [] });
  if (criar.status !== 201) {
    const motivo = MSG[criar.json.codigo] ?? `erro ${criar.status} ${criar.json.codigo ?? ''}`;
    resultado.push({ ...p, situacao: motivo, link: '', expira: '' });
    console.log(`  ✗ ${p.email}: ${motivo}`);
    continue;
  }
  const link = await chamar('POST', 'admin/usuarios/link-senha', { id: criar.json.id });
  if (link.status !== 200) {
    resultado.push({ ...p, situacao: `criado, link falhou (${link.json.codigo ?? link.status})`, link: '', expira: '' });
    console.log(`  ! ${p.email}: criado, mas o link falhou`);
    continue;
  }
  const expira = new Date(link.json.expiraEm).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  resultado.push({ ...p, situacao: 'criado', link: link.json.link, expira });
  console.log(`  ✓ ${p.email} (${p.perfil})`);
}
await chamar('POST', 'auth/logout', {});

const esc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
writeFileSync(SAIDA, '﻿' + ['nome;email;perfil;situacao;link;vale_ate']
  .concat(resultado.map((r) => [r.nome, r.email, r.perfil, r.situacao, r.link, r.expira].map(esc).join(';')))
  .join('\r\n') + '\r\n');
const criados = resultado.filter((r) => r.situacao === 'criado').length;
console.log(`\n${criados} criado(s), ${resultado.length - criados} não criado(s). Links em ${SAIDA} (valem 24 h; não compartilhe este arquivo).`);

function sair(msg) {
  console.error(msg);
  process.exit(1);
}
