import { describe, expect, it } from 'vitest';

import { desde, diaSemana, hm, larguraBarra, nivelDias, tratativaValida } from './jornada';

describe('Jornada · domínio', () => {
  it('horas e minutos', () => {
    expect(hm(770)).toBe('12h50');
    expect(hm(5)).toBe('0h05');
    expect(hm(null)).toBe('—');
    expect(desde('2026-11-22T00:00:00Z', new Date('2026-11-23T12:10:00Z'))).toBe('36h10');
  });

  it('barra sobre 13 h', () => {
    expect(larguraBarra(390)).toBeCloseTo(50);
    expect(larguraBarra(900)).toBe(100);
    expect(larguraBarra(null)).toBe(0);
  });

  it('dias sem DSR: 6 atenção, 7+ violação', () => {
    expect(nivelDias(5)).toBe('neutro');
    expect(nivelDias(6)).toBe('atencao');
    expect(nivelDias(8)).toBe('violacao');
  });

  it('tratativa "Outro" exige observação (R10)', () => {
    expect(tratativaValida('outro', '  ')).not.toBeNull();
    expect(tratativaValida('outro', 'ficou no pátio')).toBeNull();
    expect(tratativaValida('dsr_confirmado', '')).toBeNull();
    expect(tratativaValida('', '')).not.toBeNull();
  });

  it('dia da semana', () => {
    expect(diaSemana('2026-11-23')).toBe('Seg 23/11');
  });
});
