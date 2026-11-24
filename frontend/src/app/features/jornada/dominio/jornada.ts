// Domínio da tela de Jornada (spec jornada-painel). Puro TypeScript, sem Angular.

export type NivelJornada = 'violacao' | 'conferir' | 'atencao' | 'dentro';
export type Faixa = '' | 'violacao' | 'conferir' | 'atencao' | 'dsr' | 'jornada' | 'tratados';
export type FiltroDias = '' | '0-2' | '3-5' | '6' | '7+';

export interface AlertaJornada {
  codigo: string;
  nivel: 'violacao' | 'atencao' | 'conferir';
  valor: string;
  texto: string;
}

export interface Tratativa {
  tipo: string;
  observacao: string | null;
  em: string;
  por: string;
  jornadaId?: string | null;
}

export interface MotoristaJornada {
  id: string;
  nome: string;
  placa: string | null;
  semControle: boolean;
  status: string;
  nivel: NivelJornada;
  jornadaAtual: { inicio: string; trabalhoMin: number | null; amplitudeMin: number | null; nivel: string | null; maxContinuaMin: number | null } | null;
  paradoDesde: string | null;
  local: string | null;
  diasSemDsr: number;
  ultimoDsr: string | null;
  semanaMin: number;
  alertas: AlertaJornada[];
  macrosDesconhecidas: number;
  tratativa: Tratativa | null;
  atualizadoEm: string | null;
}

export interface JornadaDia {
  id: string;
  dia: string;
  inicio: string;
  fim: string | null;
  situacao: 'ok' | 'em_curso' | 'sem_fim' | 'inconsistente';
  nivel: 'dentro' | 'atencao' | 'violacao' | null;
  trabalhoMin: number | null;
  refeicaoMin: number | null;
  direcaoMin: number | null;
  maxContinuaMin: number | null;
  interjornadaMin: number | null;
  motivos: AlertaJornada[];
}

export interface DetalheMotorista extends MotoristaJornada {
  jornadas: JornadaDia[];
  paradas: { inicio: string; fim: string; minutos: number; contaDsr: boolean; kmTelemetria: number | null; local: string | null; motivo: string }[];
  macros: { horario: string; numero: number; local: string | null; significado: string | null; desconhecida: boolean }[];
  tratativas: Tratativa[];
}

export interface ResumoJornada {
  todos: number;
  violacao: number;
  conferir: number;
  atencao: number;
  dsr: number;
  jornada: number;
  tratados: number;
  retrato: string | null;
}

export const FAIXAS: { chave: Faixa; nome: string; sub: string; cor: NivelJornada | 'neutro' }[] = [
  { chave: '', nome: 'Todos', sub: 'com controle', cor: 'neutro' },
  { chave: 'violacao', nome: 'Violação', sub: 'fora da lei', cor: 'violacao' },
  { chave: 'conferir', nome: 'Conferir', sub: 'parado / telemetria', cor: 'conferir' },
  { chave: 'atencao', nome: 'Atenção', sub: 'perto do limite', cor: 'atencao' },
  { chave: 'dsr', nome: 'Parado 35 h+', sub: 'considerar descanso', cor: 'conferir' },
  { chave: 'jornada', nome: 'Em jornada', sub: 'agora', cor: 'dentro' },
  { chave: 'tratados', nome: 'Tratados', sub: 'últimas 24 h', cor: 'dentro' },
];

export const NOME_STATUS: Record<string, string> = {
  dirigindo: 'Dirigindo', em_jornada: 'Em jornada', em_servico: 'Em serviço', refeicao: 'Refeição',
  parada_descanso: 'Parada/descanso', fora_jornada: 'Fora de jornada', sem_eventos: 'Sem eventos',
};

export const COR_STATUS: Record<string, NivelJornada | 'neutro'> = {
  dirigindo: 'dentro', em_jornada: 'dentro', em_servico: 'dentro', refeicao: 'atencao',
  parada_descanso: 'neutro', fora_jornada: 'neutro', sem_eventos: 'neutro',
};

export const TIPOS_TRATATIVA: { valor: string; nome: string }[] = [
  { valor: 'dsr_confirmado', nome: 'DSR confirmado (descanso)' },
  { valor: 'tempo_espera', nome: 'Tempo de espera (conta jornada)' },
  { valor: 'macro_errada', nome: 'Macro errada – corrigir' },
  { valor: 'jornada_correta', nome: 'Jornada correta' },
  { valor: 'orientado_advertido', nome: 'Orientado / advertido' },
  { valor: 'outro', nome: 'Outro' },
];

export const NOME_TRATATIVA: Record<string, string> = Object.fromEntries(TIPOS_TRATATIVA.map((t) => [t.valor, t.nome]));

export const NOME_SITUACAO: Record<string, string> = { ok: 'Fechada', em_curso: 'Em curso', sem_fim: 'Sem fim', inconsistente: 'Inconsistente' };

export const NOME_MACRO: Record<string, string> = {
  inicio_jornada: 'Início de jornada', fim_jornada: 'Fim de jornada', inicio_refeicao: 'Início de refeição', fim_refeicao: 'Fim de refeição',
  inicio_parada: 'Início de parada', fim_parada: 'Fim de parada', inicio_espera: 'Início de espera', fim_espera: 'Fim de espera', ignorar: 'Ignorada',
};

export const LIMITE_BARRA_MIN = 13 * 60;

export function hm(min: number | null | undefined): string {
  if (min === null || min === undefined) return '—';
  return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`;
}

/** "36h10" desde uma data. */
export function desde(iso: string | null, agora: Date): string {
  if (!iso) return '—';
  return hm(Math.max(0, Math.floor((agora.getTime() - new Date(iso).getTime()) / 60000)));
}

/** Largura da barra da jornada (0–100) sobre 13 h. */
export function larguraBarra(min: number | null | undefined): number {
  return Math.min(100, Math.max(0, ((min ?? 0) / LIMITE_BARRA_MIN) * 100));
}

export function dataHora(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

export function hora(iso: string | null): string {
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : '—';
}

export function diaSemana(isoDia: string): string {
  const d = new Date(isoDia + 'T12:00:00');
  const dia = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'][d.getDay()];
  return `${dia} ${isoDia.slice(8, 10)}/${isoDia.slice(5, 7)}`;
}

/** Nível do contador de dias sem DSR (6 atenção, 7+ violação). */
export function nivelDias(dias: number): NivelJornada | 'neutro' {
  return dias >= 7 ? 'violacao' : dias >= 6 ? 'atencao' : 'neutro';
}

/** Observação é obrigatória quando o tipo é "Outro" (R10). */
export function tratativaValida(tipo: string, observacao: string): string | null {
  if (!tipo) return 'Escolha o tipo da tratativa.';
  if (tipo === 'outro' && !observacao.trim()) return 'Descreva a tratativa quando o tipo é "Outro".';
  return null;
}

export function mensagemJornada(codigo: string): string {
  const m: Record<string, string> = {
    OBSERVACAO_OBRIGATORIA: 'Descreva a tratativa quando o tipo é "Outro".',
    TIPO_INVALIDO: 'Escolha um tipo de tratativa da lista.',
    NAO_ENCONTRADO: 'Este motorista não está mais disponível.',
    SEM_PERMISSAO: 'Seu perfil não pode registrar tratativa.',
    CSRF: 'A sessão mudou em outra aba. Recarregue a página.',
  };
  return m[codigo] ?? 'Não foi possível concluir agora. Tente de novo em alguns segundos.';
}
