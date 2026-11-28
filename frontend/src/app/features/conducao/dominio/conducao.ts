export const TIPOS_CONDUCAO = {
  aceleracao_brusca: 'Aceleração brusca',
  freada_brusca: 'Freada brusca',
  banguela: 'Banguela',
  fora_faixa_verde: 'Fora da faixa verde',
  rpm_excessiva: 'RPM excessiva',
  velocidade_excessiva: 'Velocidade excessiva',
  velocidade_excessiva_chuva: 'Velocidade excessiva na chuva',
  marcha_lenta_excessiva: 'Marcha lenta excessiva',
  pressao_oleo_baixa: 'Pressão do óleo baixa',
  pressao_oleo_alta: 'Pressão do óleo alta',
};

export interface FiltrosConducao {
  periodo: string;
  placa: string;
  tipo: string;
  motorista?: string;
  operacao?: string;
}

export interface PaginaConducao {
  eventos: {
    horario: string;
    placa: string;
    motorista: string | null;
    tipo: keyof typeof TIPOS_CONDUCAO;
  }[];
  proximo: string | null;
  atualizadoEm: string | null;
  estado: 'ok' | 'atraso' | 'erro' | 'inativa';
}

// ===== Segunda entrega: ranking (spec relatorio-conducao R5–R13) =====

export type VisaoConducao = 'motorista' | 'caminhao';

export interface LinhaRanking {
  chave: string;
  nome: string;
  sub: string;
  cadastrado: boolean;
  outros: number;      // caminhões (visão motorista) ou motoristas (visão caminhão)
  km: number;
  total: number;
  taxa: number | null; // eventos por 100 km; null = km insuficiente
  vezes: number | null; // taxa ÷ média da frota
  velocidade: number;
  rpm: number;
  faixa: number;
  faixaMin: number;
  lenta: number;
  lentaMin: number;
  banguela: number;
  bruscas: number;
  oleo: number;
}

export interface RankingConducao {
  visao: VisaoConducao;
  linhas: LinhaRanking[];
  resumo: { eventos: number; km: number; media: number | null; acimaDe2x: number };
  dadosAte: string | null;
  estado: 'ok' | 'atraso' | 'erro' | 'inativa';
}

export interface DetalheConducao {
  dias: { dia: string; eventos: number }[];
  outros: string[];
  ultimos: { horario: string; tipo: keyof typeof TIPOS_CONDUCAO; placa: string; motorista: string; minutos: number | null }[];
}

export interface FiltrosRanking {
  periodo: string;
  visao: VisaoConducao;
  tipo: string;
  q: string;
}

const numero = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
export const fmt = (n: number | null | undefined): string => (n === null || n === undefined ? '—' : numero.format(n));

/** R10: o destaque vem sempre com texto, nunca só pela cor. */
export function textoVezes(l: Pick<LinhaRanking, 'taxa' | 'vezes'>): string {
  if (l.taxa === null) return 'km insuficiente';
  if (l.vezes === null) return '';
  if (l.vezes >= 1.15) return `${fmt(l.vezes)}× a média`;
  if (l.vezes <= 0.85) return 'abaixo da média';
  return 'na média';
}

export const acimaDoDobro = (l: Pick<LinhaRanking, 'vezes'>): boolean => l.vezes !== null && l.vezes >= 2;

/** R13: planilha (CSV com ";" e BOM, abre certo no Excel em português). */
export function csvRanking(r: RankingConducao, periodo: string): string {
  const motorista = r.visao === 'motorista';
  const cab = [motorista ? 'Motorista' : 'Caminhão', motorista ? 'Situação' : 'Operação', motorista ? 'Caminhões' : 'Motoristas',
    'Km', 'Eventos', 'Eventos por 100 km', 'Vezes a média', 'Velocidade', 'RPM', 'Fora da faixa verde', 'Minutos fora da faixa',
    'Marcha lenta', 'Minutos em marcha lenta', 'Banguela', 'Acelerações e freadas bruscas', ...(motorista ? [] : ['Pressão do óleo']), 'Período'];
  const cel = (v: unknown) => {
    const t = v === null || v === undefined ? '' : String(v);
    return /[;"\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
  };
  const dec = (n: number | null) => (n === null ? '' : String(n).replace('.', ','));
  const linhas = r.linhas.map((l) => [l.nome, l.sub, l.outros, l.km, l.total, dec(l.taxa), dec(l.vezes), l.velocidade, l.rpm, l.faixa,
    l.faixaMin, l.lenta, l.lentaMin, l.banguela, l.bruscas, ...(motorista ? [] : [l.oleo]), periodo].map(cel).join(';'));
  return '﻿' + [cab.map(cel).join(';'), ...linhas].join('\r\n');
}
