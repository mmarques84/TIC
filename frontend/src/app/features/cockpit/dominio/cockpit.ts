import { FiltrosConducao, PaginaConducao, TIPOS_CONDUCAO } from '../../conducao/dominio/conducao';

export interface FiltrosCockpit extends FiltrosConducao {
  operacao: string;
}

export interface ResumoCockpit {
  total: number;
  dias: { dia: string; total: number }[];
  tipos: { tipo: keyof typeof TIPOS_CONDUCAO; total: number }[];
  motoristas: { id: string; nome: string; cadastrado: boolean; placas: string[]; total: number }[];
  veiculos: { placa: string; total: number }[];
  limiteDestaques: number;
  semMotorista: number;
  operacoes: { id: string; nome: string }[];
  atualizadoEm: PaginaConducao['atualizadoEm'];
  estado: PaginaConducao['estado'];
}
