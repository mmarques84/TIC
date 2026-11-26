// Código dos nós Code dos workflows ing-autotrac-* (spec ingestao-autotrac). Adaptador: só monta as chamadas e junta as páginas.
// Toda regra (placa, mapa, deduplicação, saneamento, janelas) está nas funções job_* do banco.
// Nunca colocar credencial em item, log ou erro: o cabeçalho de login vem da credencial do n8n.

// @no Chamadas
// Uma chamada por veículo × janela × tipo (telemetria e câmera). Bloqueado (401/403) ou sem lote: não busca nada.
const r = $input.first().json.r || {};
if (r.bloqueado || !r.lote) return [];
const base = String(r.url || '').replace(/\/$/, '');
const out = [];
for (const c of r.chamadas || []) {
  for (const tipo of ['telemetria', 'sds']) {
    const recurso = tipo === 'sds' ? 'safetydrivingevents' : 'alltelemetryevents';
    out.push({ json: {
      lote: r.lote, veiculo: c.veiculo, codigo: c.codigo, tipo,
      url: `${base}/v1/accounts/${r.conta}/vehicles/${c.codigo}/${recurso}?_dateTimeFrom=${c.de}&_dateTimeTo=${c.ate}&_limit=100`,
    } });
  }
}
return out;

// @no Agrupar
// Junta as páginas de cada chamada (pairedItem aponta para a chamada de origem). Erro HTTP vira falha, sem o corpo da resposta.
const chamadas = $('Chamadas').all();
const grupos = new Map();
for (const item of $input.all()) {
  const idx = (Array.isArray(item.pairedItem) ? item.pairedItem[0] : item.pairedItem)?.item ?? 0;
  const ch = chamadas[idx].json;
  const g = grupos.get(idx) || { lote: ch.lote, veiculo: ch.veiculo, codigo: ch.codigo, tipo: ch.tipo, itens: [], http: null };
  const j = item.json || {};
  if (j.error) {
    const e = j.error;
    const m = String(e.httpCode || e.statusCode || e.status || (String(e.message || '').match(/\b([45]\d\d)\b/) || [])[1] || 0);
    g.http = Number(m) || 500; // erro sem código HTTP (rede, tempo, paginação) também é falha
  } else {
    g.itens.push(...(Array.isArray(j.Data) ? j.Data : Array.isArray(j) ? j : []));
  }
  grupos.set(idx, g);
}
return [...grupos.values()].map((g) => ({ json: { ...g, itensJson: JSON.stringify(g.http ? [] : g.itens) } }));

// @no Resumo do ciclo
// Falhas (sem dado sensível) e o resultado para controle.credencial_status.
const grupos = $('Agrupar').all().map((i) => i.json);
const falhas = grupos.filter((g) => g.http).map((g) => ({ placa: `Autotrac ${g.codigo} (${g.tipo})`, http: g.http }));
const bloqueio = falhas.find((f) => f.http === 401 || f.http === 403);
const primeira = bloqueio || falhas[0];
return [{ json: {
  lote: grupos[0] ? grupos[0].lote : null,
  falhasJson: JSON.stringify(falhas),
  ok: falhas.length === 0 ? 'true' : 'false',
  http: primeira ? String(primeira.http) : '',
  erro: primeira ? `HTTP ${primeira.http} em ${falhas.length} de ${grupos.length} chamada(s) da Autotrac` : '',
} }];

// @no Preparar frota
const r = $input.first().json.r || {};
if (r.bloqueado || !r.lote) return [];
const base = String(r.url || '').replace(/\/$/, '');
return [{ json: { lote: r.lote, url: `${base}/v1/accounts/${r.conta}/vehicles?_limit=100` } }];

// @no Juntar frota
const lote = $('Preparar frota').first().json.lote;
let http = 0; const itens = [];
for (const item of $input.all()) {
  const j = item.json || {};
  if (j.error) {
    const e = j.error;
    http = Number(e.httpCode || e.statusCode || e.status || (String(e.message || '').match(/\b([45]\d\d)\b/) || [])[1] || 0) || 500;
  } else itens.push(...(Array.isArray(j.Data) ? j.Data : []));
}
// Com erro não aplica lista parcial (placa repetida só se vê com a frota inteira).
return [{ json: {
  lote,
  itensJson: JSON.stringify(http ? [] : itens),
  falhasJson: JSON.stringify(http ? [{ placa: 'frota', http }] : []),
  ok: http ? 'false' : 'true',
  http: http ? String(http) : '',
  erro: http ? `HTTP ${http} ao buscar a frota na Autotrac` : '',
  veiculos: itens.length,
} }];

// @no Chamadas ATIC
// Fase B: por veículo × janela, os três recursos da ATIC. Login primeiro (a macro precisa saber quem estava logado).
// A ATIC exige a data com fuso (+00:00, codificado na URL).
const r = $input.first().json.r || {};
if (r.bloqueado || !r.lote) return [];
const base = String(r.url || '').replace(/\/$/, '');
const data = (d) => encodeURIComponent(d + '+00:00');
const out = [];
for (const c of r.chamadas || []) {
  for (const tipo of ['driverlogs', 'positions', 'returnmessages']) {
    out.push({ json: {
      lote: r.lote, veiculo: c.veiculo, codigo: c.codigo, tipo,
      url: `${base}/v1/accounts/${r.conta}/vehicles/${c.codigo}/${tipo}?_dateTimeFrom=${data(c.de)}&_dateTimeTo=${data(c.ate)}&_limit=100`,
    } });
  }
}
return out;
