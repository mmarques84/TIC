// Domínio de acesso: puro TypeScript, sem Angular. Espelha acesso.perfil e acesso.permissao do banco.

export type Perfil = 'diretoria' | 'operacao' | 'frota_opi' | 'central' | 'ti' | 'admin';

export type Permissao =
  | 'alerta.ver'
  | 'alerta.tratar'
  | 'alerta.acionar'
  | 'imagem.ver'
  | 'jornada.ver'
  | 'conducao.ver'
  | 'jornada.tratar'
  | 'torre.ver'
  | 'opi.ver'
  | 'opi.validar'
  | 'triagem.validar'
  | 'cockpit.ver'
  | 'consumo_ia.ver'
  | 'parametro.ver'
  | 'parametro.editar'
  | 'usuario.gerir'
  | 'integracao.ver'
  | 'auditoria.ver';

export interface Usuario {
  id: string;
  nome: string;
  email: string;
  perfil: Perfil;
  permissoes: readonly Permissao[];
  operacoes: readonly string[]; // nomes das operações que vê; vazio + todasOperacoes = todas
  todasOperacoes: boolean;
}

export const NOME_PERFIL: Record<Perfil, string> = {
  diretoria: 'Diretoria',
  operacao: 'Operação',
  frota_opi: 'Frota/OPI',
  central: 'Central',
  ti: 'TI',
  admin: 'Admin',
};

export function pode(usuario: Usuario | null, permissao: Permissao): boolean {
  return !!usuario && usuario.permissoes.includes(permissao);
}

export function primeiroNome(usuario: Usuario | null): string {
  return usuario?.nome.trim().split(/\s+/)[0] ?? '';
}
