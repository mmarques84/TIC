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

// Ordem do Roteiro Técnico V2 (24/11/2026): Central de alertas, Cockpit gerencial, Cockpit OPI, Jornada,
// Torre de chegadas, Consumo de IA e Admin. O que não está no roteiro fica em "Apoio".
export const MENU: GrupoMenu[] = [
  { nome: 'Geral', itens: [{ rotulo: 'Início', rota: '/inicio', permissao: null }] },
  {
    nome: 'Painéis',
    itens: [
      { rotulo: 'Central de alertas', rota: '/alertas', permissao: 'alerta.ver' },
      { rotulo: 'Cockpit gerencial', rota: '/cockpit', permissao: 'cockpit.ver' },
      { rotulo: 'Cockpit OPI', rota: '/opi', permissao: 'opi.ver' },
      { rotulo: 'Jornada', rota: '/jornada', permissao: 'jornada.ver' },
      { rotulo: 'Condução', rota: '/conducao', permissao: 'conducao.ver' },
      { rotulo: 'Torre de chegadas', rota: '/torre', permissao: 'torre.ver' },
      { rotulo: 'Consumo de IA', rota: '/consumo-ia', permissao: 'consumo_ia.ver' },
    ],
  },
  {
    nome: 'Apoio',
    itens: [
      { rotulo: 'Validar triagem da IA', rota: '/triagem', permissao: 'triagem.validar' },
      { rotulo: 'Entregas', rota: '/entregas', permissao: 'torre.ver', emBreve: true },
    ],
  },
  {
    nome: 'Admin',
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
