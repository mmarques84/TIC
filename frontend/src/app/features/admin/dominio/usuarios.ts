// Domínio do Admin · Usuários e perfis (spec admin-usuarios). Puro TypeScript, sem Angular.

export interface OperacaoRef {
  id: string;
  nome: string;
}

export interface UsuarioAdmin {
  id: string;
  nome: string;
  email: string;
  perfil: string;
  perfilNome: string;
  todasOperacoes: boolean;
  operacoes: OperacaoRef[];
  ativo: boolean;
  temSenha: boolean;
  bloqueado: boolean;
  ultimoAcesso: string | null;
  sessoesAbertas: number;
}

export interface PerfilOpcao {
  codigo: string;
  nome: string;
  descricao: string;
}

export interface SessaoAberta {
  id: string;
  criadaEm: string;
  ultimoUsoEm: string;
  expiraEm: string;
  ip: string | null;
  userAgent: string | null;
}

export interface LinkGerado {
  link: string;
  expiraEm: string;
  tipo: 'convite' | 'recuperacao';
}

const semAcento = (t: string) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** R3: busca por nome ou e-mail sem diferenciar maiúsculas e acentos; filtro por perfil. */
export function filtrar(lista: UsuarioAdmin[], busca: string, perfil: string): UsuarioAdmin[] {
  const q = semAcento(busca.trim());
  return lista.filter((u) => (!perfil || u.perfil === perfil) && (!q || semAcento(`${u.nome} ${u.email}`).includes(q)));
}

export function operacoesTexto(u: UsuarioAdmin): string {
  return u.todasOperacoes ? 'Todas' : u.operacoes.map((o) => o.nome).join(', ') || '—';
}

export function contagem(lista: UsuarioAdmin[]): string {
  const ativos = lista.filter((u) => u.ativo).length;
  return `${lista.length} ${lista.length === 1 ? 'pessoa' : 'pessoas'} · ${ativos} ${ativos === 1 ? 'ativa' : 'ativas'}`;
}

export function dataHora(iso: string | null): string {
  if (!iso) return 'nunca';
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

/** "Chrome · Windows" a partir do user-agent (aproximado, só para reconhecer o aparelho). */
export function aparelho(ua: string | null): string {
  if (!ua) return 'Navegador desconhecido';
  const nav = /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : /curl\//.test(ua) ? 'curl' : 'Navegador';
  const so = /Windows/.test(ua) ? 'Windows' : /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Mac OS/.test(ua) ? 'Mac' : /Linux/.test(ua) ? 'Linux' : '';
  return so ? `${nav} · ${so}` : nav;
}

/** Mensagem para a pessoa a partir do código de erro do backend. */
export function mensagemAdmin(codigo: string): string {
  const m: Record<string, string> = {
    EMAIL_JA_CADASTRADO: 'Este e-mail já está cadastrado.',
    EMAIL_INVALIDO: 'Digite um e-mail válido.',
    NOME_OBRIGATORIO: 'Informe o nome (pelo menos 2 letras).',
    PERFIL_INVALIDO: 'Escolha um perfil da lista.',
    USUARIO_INATIVO: 'Ative o usuário antes de gerar o link.',
    ULTIMO_ADMIN: 'O portal precisa de pelo menos um administrador ativo.',
    PROPRIO_USUARIO: 'Você não pode desativar nem mudar o perfil do seu próprio acesso.',
    NAO_ENCONTRADO: 'Este registro não existe mais. Atualize a lista.',
    SEM_PERMISSAO: 'Seu perfil não pode administrar usuários.',
    CSRF: 'A sessão mudou em outra aba. Recarregue a página.',
  };
  return m[codigo] ?? 'Não foi possível concluir agora. Tente de novo em alguns segundos.';
}
