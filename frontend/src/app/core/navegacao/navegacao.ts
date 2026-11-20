import { Permissao } from '../auth/dominio/usuario';

// Itens do menu por grupo. Quem vê cada item = permissão (acesso.perfil_permissao no banco).
export interface ItemMenu {
  rotulo: string;
  rota: string;
  permissao: Permissao | null; // null = todos logados
  emBreve?: boolean;           // fase 2: aparece desativado
}

export interface GrupoMenu {
  nome: string;
  itens: ItemMenu[];
}

export const MENU: GrupoMenu[] = [
  { nome: 'Geral', itens: [{ rotulo: 'Início', rota: '/inicio', permissao: null }] },
  {
    nome: 'Operação',
    itens: [
      { rotulo: 'Central de alertas', rota: '/alertas', permissao: 'alerta.ver' },
      { rotulo: 'Jornada', rota: '/jornada', permissao: 'jornada.ver' },
      { rotulo: 'Torre de chegadas', rota: '/torre', permissao: 'torre.ver' },
      { rotulo: 'Entregas', rota: '/entregas', permissao: 'torre.ver', emBreve: true },
    ],
  },
  {
    nome: 'Frota e segurança',
    itens: [
      { rotulo: 'OPI', rota: '/opi', permissao: 'opi.ver' },
      { rotulo: 'Validar triagem da IA', rota: '/triagem', permissao: 'triagem.validar' },
    ],
  },
  {
    nome: 'Gestão',
    itens: [
      { rotulo: 'Cockpit gerencial', rota: '/cockpit', permissao: 'cockpit.ver' },
      { rotulo: 'Consumo de IA', rota: '/consumo-ia', permissao: 'consumo_ia.ver' },
    ],
  },
  {
    nome: 'Administração',
    itens: [
      { rotulo: 'Usuários e perfis', rota: '/admin/usuarios', permissao: 'usuario.gerir' },
      { rotulo: 'Parâmetros das regras', rota: '/admin/parametros', permissao: 'parametro.ver' },
      { rotulo: 'Integrações', rota: '/admin/integracoes', permissao: 'integracao.ver' },
      { rotulo: 'Auditoria', rota: '/admin/auditoria', permissao: 'auditoria.ver' },
    ],
  },
];

/** Itens (não fase 2) que viram rota "em construção" até a tela existir. */
export const ITENS_COM_ROTA = MENU.flatMap((g) => g.itens).filter((i) => !i.emBreve && i.rota !== '/inicio');

export function menuDoUsuario(pode: (p: Permissao) => boolean): GrupoMenu[] {
  return MENU.map((g) => ({ ...g, itens: g.itens.filter((i) => i.permissao === null || pode(i.permissao)) })).filter((g) => g.itens.length > 0);
}
