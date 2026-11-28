import { describe, expect, it } from 'vitest';

import { RankingConducao, acimaDoDobro, csvRanking, textoVezes } from './conducao';

const linha = (taxa: number | null, vezes: number | null) => ({ taxa, vezes });

describe('Condução · domínio', () => {
  it('R10: destaque sempre com texto', () => {
    expect(textoVezes(linha(null, null))).toBe('km insuficiente');
    expect(textoVezes(linha(9.2, 2.3))).toBe('2,3× a média');
    expect(textoVezes(linha(3, 1))).toBe('na média');
    expect(textoVezes(linha(1, 0.5))).toBe('abaixo da média');
    expect(acimaDoDobro({ vezes: 2 })).toBe(true);
    expect(acimaDoDobro({ vezes: 1.9 })).toBe(false);
    expect(acimaDoDobro({ vezes: null })).toBe(false);
  });

  it('R13: planilha com ";", BOM, decimais com vírgula e aspas quando precisa', () => {
    const r: RankingConducao = {
      visao: 'motorista', dadosAte: null, estado: 'ok',
      resumo: { eventos: 3, km: 100, media: 3, acimaDe2x: 0 },
      linhas: [{ chave: 'x', nome: 'Silva; João', sub: 'cód. Autotrac 1 · não cadastrado', cadastrado: false, outros: 1, km: 100, total: 3,
        taxa: 3.5, vezes: 1.2, velocidade: 1, rpm: 1, faixa: 0, faixaMin: 0, lenta: 1, lentaMin: 10, banguela: 0, bruscas: 0, oleo: 0 }],
    };
    const csv = csvRanking(r, 'últimos 7 dias');
    expect(csv.startsWith('﻿Motorista;')).toBe(true);
    const [, l1] = csv.split('\r\n');
    expect(l1.startsWith('"Silva; João";')).toBe(true);
    expect(l1).toContain(';3,5;1,2;');
    expect(csv).not.toContain('Pressão do óleo');
  });
});
