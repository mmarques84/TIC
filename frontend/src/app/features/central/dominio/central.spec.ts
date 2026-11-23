import { describe, expect, it } from 'vitest';

import { AlertaFila, criticosNovos, haQuanto, minutosDesde, semAtualizacao, situacao, textoIA } from './central';

const agora = new Date('2026-11-20T12:00:00Z');
const a = (id: string, nivel: AlertaFila['nivel'], extra: Partial<AlertaFila> = {}): AlertaFila => ({
  id, nivel, estado: 'aberto', titulo: 't', tipo: 'fadiga', horario: '2026-11-20T11:50:00Z', placa: 'TST1A01', motorista: null, local: null,
  velocidade: null, ia: null, assumidoPor: null, tratadoPor: null, tratadoEm: null, motivoFalso: null, ultimaAcao: null, fotoCapa: null, cameraCapa: null, ...extra,
});

describe('Central · domínio', () => {
  it('há quanto tempo', () => {
    expect(haQuanto('2026-11-20T11:57:00Z', agora)).toBe('há 3 min');
    expect(haQuanto('2026-11-20T10:00:00Z', agora)).toBe('há 2 h');
    expect(haQuanto('2026-11-20T11:59:40Z', agora)).toBe('agora');
    expect(minutosDesde('2026-11-20T10:29:00Z', agora)).toBe('1h31');
  });

  it('texto da IA', () => {
    expect(textoIA({ resultado: 'verdadeiro', confianca: 'media', evidencia: '' })).toBe('IA: verdadeiro · média');
    expect(textoIA(null)).toBe('sem triagem da IA');
  });

  it('situação da linha', () => {
    expect(situacao(a('1', 'grave', { assumidoPor: 'Ana' }))).toBe('com Ana');
    expect(situacao(a('1', 'grave', { ultimaAcao: { tipo: 'sirene', estado: 'enviada', automatica: true } }))).toBe('Sirene enviada');
    expect(situacao(a('1', 'grave'))).toBe('aguardando');
  });

  it('TV sem atualização há mais de 1 min (R20)', () => {
    expect(semAtualizacao(new Date('2026-11-20T11:59:30Z'), agora)).toBe(false);
    expect(semAtualizacao(new Date('2026-11-20T11:58:30Z'), agora)).toBe(true);
    expect(semAtualizacao(null, agora)).toBe(true);
  });

  it('crítico novo só depois da primeira leitura (R6)', () => {
    expect(criticosNovos(null, [a('1', 'critico')])).toEqual([]);
    expect(criticosNovos(new Set(['1']), [a('1', 'critico'), a('2', 'critico'), a('3', 'grave')])).toEqual(['2']);
  });
});
