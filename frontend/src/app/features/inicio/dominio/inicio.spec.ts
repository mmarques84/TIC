import { describe, expect, it } from 'vitest';

import { Indicador, composicaoDoPerfil, indicadoresDoPerfil, saudacao } from './inicio';

const ind = (codigo: Indicador['codigo']): Indicador => ({ codigo, rotulo: codigo, valor: '1', nota: '', nivelNota: null });
const todos = (['alertas', 'fadiga', 'em_jornada', 'violacoes', 'falsos_evitados', 'opi_mes', 'consumo_ia', 'integracoes'] as const).map(ind);

describe('Início · domínio', () => {
  it('cada perfil vê 4 indicadores, na ordem do perfil', () => {
    expect(indicadoresDoPerfil('operacao', todos).map((i) => i.codigo)).toEqual(['alertas', 'fadiga', 'em_jornada', 'violacoes']);
    expect(indicadoresDoPerfil('diretoria', todos)).toHaveLength(4);
  });

  it('painel lateral por perfil', () => {
    expect(composicaoDoPerfil('frota_opi').lateral).toBe('opi');
    expect(composicaoDoPerfil('ti').alertas).toBe(false);
  });

  it('indicador ausente na resposta não quebra', () => {
    expect(indicadoresDoPerfil('operacao', [ind('alertas')])).toHaveLength(1);
  });

  it('saudação pela hora', () => {
    expect(saudacao(new Date(2026, 10, 20, 9))).toBe('Bom dia');
    expect(saudacao(new Date(2026, 10, 20, 15))).toBe('Boa tarde');
    expect(saudacao(new Date(2026, 10, 20, 21))).toBe('Boa noite');
  });
});
