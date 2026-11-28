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
