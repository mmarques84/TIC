// Domínio da tela Início: tipos e regras de composição por perfil. Puro TypeScript, sem Angular.
import { Perfil } from '../../../core/auth/dominio/usuario';

export type Nivel = 'critico' | 'grave' | 'medio' | 'leve' | 'ok' | 'neutro';

export interface Indicador {
  codigo: 'alertas' | 'fadiga' | 'em_jornada' | 'violacoes' | 'falsos_evitados' | 'opi_mes' | 'consumo_ia' | 'integracoes';
  rotulo: string;
  valor: string;
  nota: string;
  nivelNota: Nivel | null;
}

export interface LinhaAlerta {
  id: string;
  nivel: Nivel;
  rotuloNivel: string;
  titulo: string;
  detalhe: string;
  placa: string;
  motorista: string;
  ha: string;
}

export interface LinhaSimples {
  id: string;
  titulo: string;
  detalhe: string;
  selo: string;
  nivel: Nivel;
}

export interface Integracao {
  fonte: string;
  estado: 'ok' | 'atraso' | 'erro' | 'inativa';
  texto: string;
}

/** O que a API devolve: todos os blocos que o usuário pode ver. */
export interface ResumoInicio {
  geradoEm: string;
  indicadores: Indicador[];
  alertas: LinhaAlerta[];
  jornada: LinhaSimples[];
  opi: LinhaSimples[];
  consumo: LinhaSimples[];
  integracoes: Integracao[];
}

export type PainelLateral = 'jornada' | 'opi' | 'consumo' | 'integracoes';

export const TITULO_PAINEL: Record<PainelLateral, { titulo: string; link: string; rota: string }> = {
  jornada: { titulo: 'Jornada: atenção agora', link: 'Abrir jornada', rota: '/jornada' },
  opi: { titulo: 'OPIs do mês', link: 'Abrir OPI', rota: '/opi' },
  consumo: { titulo: 'Consumo de IA por agente', link: 'Abrir consumo', rota: '/consumo-ia' },
  integracoes: { titulo: 'Integrações', link: 'Abrir integrações', rota: '/admin/integracoes' },
};

const POR_PERFIL: Record<Perfil, { indicadores: Indicador['codigo'][]; lateral: PainelLateral; alertas: boolean }> = {
  diretoria: { indicadores: ['alertas', 'falsos_evitados', 'opi_mes', 'consumo_ia'], lateral: 'consumo', alertas: true },
  operacao: { indicadores: ['alertas', 'fadiga', 'em_jornada', 'violacoes'], lateral: 'jornada', alertas: true },
  frota_opi: { indicadores: ['alertas', 'falsos_evitados', 'opi_mes', 'violacoes'], lateral: 'opi', alertas: true },
  central: { indicadores: ['alertas', 'fadiga', 'em_jornada', 'integracoes'], lateral: 'integracoes', alertas: true },
  ti: { indicadores: ['integracoes', 'consumo_ia', 'alertas', 'em_jornada'], lateral: 'integracoes', alertas: false },
  admin: { indicadores: ['alertas', 'violacoes', 'consumo_ia', 'integracoes'], lateral: 'integracoes', alertas: true },
};

export function composicaoDoPerfil(perfil: Perfil) {
  return POR_PERFIL[perfil];
}

export function indicadoresDoPerfil(perfil: Perfil, todos: Indicador[]): Indicador[] {
  return POR_PERFIL[perfil].indicadores.map((c) => todos.find((i) => i.codigo === c)).filter((i): i is Indicador => !!i);
}

export function saudacao(agora: Date): string {
  const h = agora.getHours();
  return h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
}
