// Domínio da Central de alertas (spec central-alertas). Puro TypeScript, sem Angular.

export type Nivel = 'critico' | 'grave' | 'medio' | 'leve';
export type EstadoAlerta = 'aberto' | 'em_tratamento' | 'confirmado' | 'falso_positivo' | 'encerrado';

export interface Triagem {
  resultado: 'verdadeiro' | 'falso' | 'inconclusivo';
  confianca: 'alta' | 'media' | 'baixa';
  evidencia: string;
}

export interface AlertaFila {
  id: string;
  nivel: Nivel;
  estado: EstadoAlerta;
  titulo: string;
  tipo: string;
  horario: string;
  placa: string;
  motorista: string | null;
  local: string | null;
  velocidade: number | null;
  ia: Triagem | null;
  assumidoPor: string | null;
  tratadoPor: string | null;
  tratadoEm: string | null;
  motivoFalso: string | null;
  ultimaAcao: { tipo: string; estado: string; automatica: boolean } | null;
  fotoCapa: string | null;
  cameraCapa: string | null;
}

export interface AcaoFeita {
  tipo: 'mensagem_terminal' | 'sirene' | 'aviso_central';
  estado: 'pendente' | 'enviada' | 'confirmada' | 'erro';
  texto: string | null;
  em: string;
  por: string | null;
}

export interface AlertaDetalhe extends AlertaFila {
  fotos: { id: string; camera: string; instante: string }[] | null;
  podeVerFotos: boolean;
  linkClipe: string | null;
  limpador: boolean | null;
  jornada: { status: string; nivel: string } | null;
  acoes: AcaoFeita[];
  historico: { id: string; titulo: string; horario: string; estado: EstadoAlerta }[];
  mensagemPadrao: string;
}

export interface ResumoCentral {
  critico: number;
  grave: number;
  medio: number;
  leve: number;
  abertos: number;
  maisAntigo: string | null;
  geradoEm: string;
}

export const NOME_NIVEL: Record<Nivel, string> = { critico: 'Crítico', grave: 'Grave', medio: 'Médio', leve: 'Leve' };

export const TIPOS: { valor: string; nome: string }[] = [
  { valor: 'fadiga', nome: 'Fadiga' },
  { valor: 'celular', nome: 'Celular' },
  { valor: 'sem_cinto', nome: 'Sem cinto' },
  { valor: 'distracao', nome: 'Distração' },
  { valor: 'freada_brusca', nome: 'Freada brusca' },
  { valor: 'velocidade', nome: 'Velocidade' },
];

export const MOTIVOS_FALSO: { valor: string; nome: string }[] = [
  { valor: 'gesto', nome: 'Mão no rosto ou gesto' },
  { valor: 'objeto', nome: 'Objeto confundido (palito, copo, cortina)' },
  { valor: 'imagem_ruim', nome: 'Imagem ruim ou escura' },
  { valor: 'camera_desalinhada', nome: 'Câmera desalinhada' },
  { valor: 'outro', nome: 'Outro' },
];

export const NOME_CAMERA: Record<string, string> = {
  fadiga: 'Fadiga', frontal: 'Frontal', interna: 'Interna', lateral_esquerda: 'Lateral esq.', lateral_direita: 'Lateral dir.', outra: 'Outra',
};

export const NOME_ACAO: Record<string, string> = { mensagem_terminal: 'Mensagem ao terminal', sirene: 'Sirene', aviso_central: 'Aviso à central' };
export const NOME_ESTADO_ACAO: Record<string, string> = { pendente: 'pendente', enviada: 'enviada', confirmada: 'confirmada', erro: 'erro' };
export const NOME_ESTADO: Record<EstadoAlerta, string> = {
  aberto: 'aberto', em_tratamento: 'em tratamento', confirmado: 'confirmado', falso_positivo: 'falso positivo', encerrado: 'encerrado',
};

/** "há 3 min", "há 2 h", "há 1 dia". */
export function haQuanto(iso: string | null, agora: Date): string {
  if (!iso) return '—';
  const min = Math.max(0, Math.floor((agora.getTime() - new Date(iso).getTime()) / 60000));
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.floor(h / 24);
  return `há ${d} ${d === 1 ? 'dia' : 'dias'}`;
}

/** Minutos desde (para a TV: "31 min"). */
export function minutosDesde(iso: string | null, agora: Date): string {
  if (!iso) return '—';
  const min = Math.max(0, Math.floor((agora.getTime() - new Date(iso).getTime()) / 60000));
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`;
}

export function hora(iso: string | null): string {
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : '—';
}

export function textoIA(ia: Triagem | null): string {
  if (!ia) return 'sem triagem da IA';
  const conf = { alta: 'alta', media: 'média', baixa: 'baixa' }[ia.confianca];
  return `IA: ${ia.resultado} · ${conf}`;
}

/** Situação curta da linha: quem trata ou a última ação. */
export function situacao(a: AlertaFila): string {
  if (a.assumidoPor) return `com ${a.assumidoPor}`;
  if (a.ultimaAcao) return `${NOME_ACAO[a.ultimaAcao.tipo] ?? a.ultimaAcao.tipo} ${NOME_ESTADO_ACAO[a.ultimaAcao.estado] ?? ''}`.trim();
  return 'aguardando';
}

/** R20: a TV está sem atualizar há mais de 1 min? */
export function semAtualizacao(ultimaOk: Date | null, agora: Date, limiteMs = 60000): boolean {
  return !ultimaOk || agora.getTime() - ultimaOk.getTime() > limiteMs;
}

/** R6: ids de críticos que não estavam na leitura anterior. */
export function criticosNovos(antes: Set<string> | null, agora: AlertaFila[]): string[] {
  if (!antes) return []; // primeira leitura não toca
  return agora.filter((a) => a.nivel === 'critico' && !antes.has(a.id)).map((a) => a.id);
}

export function mensagemCentral(codigo: string): string {
  const m: Record<string, string> = {
    ALERTA_JA_TRATADO: 'Outra pessoa já tratou este alerta. A fila foi atualizada.',
    MOTIVO_OBRIGATORIO: 'Escolha o motivo do falso positivo.',
    TEXTO_INVALIDO: 'A mensagem precisa ter de 1 a 200 caracteres.',
    NAO_ENCONTRADO: 'Este alerta não está mais disponível.',
    SEM_PERMISSAO: 'Seu perfil não pode fazer isso.',
    CSRF: 'A sessão mudou em outra aba. Recarregue a página.',
  };
  return m[codigo] ?? 'Não foi possível concluir agora. Tente de novo em alguns segundos.';
}
