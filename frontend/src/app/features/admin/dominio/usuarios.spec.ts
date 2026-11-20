import { describe, expect, it } from 'vitest';

import { UsuarioAdmin, aparelho, contagem, filtrar, mensagemAdmin, operacoesTexto } from './usuarios';

const u = (nome: string, email: string, perfil: string, ativo = true): UsuarioAdmin => ({
  id: email, nome, email, perfil, perfilNome: perfil, todasOperacoes: true, operacoes: [], ativo,
  temSenha: true, bloqueado: false, ultimoAcesso: null, sessoesAbertas: 0,
});
const lista = [u('João Exemplo', 'joao@exemplo.com', 'central'), u('Ana', 'ana@exemplo.com', 'admin'), u('Saiu', 'saiu@exemplo.com', 'central', false)];

describe('Admin · Usuários · domínio', () => {
  it('busca sem acento e sem maiúsculas (V2)', () => {
    expect(filtrar(lista, 'JOAO', '').map((x) => x.nome)).toEqual(['João Exemplo']);
    expect(filtrar(lista, 'exemplo.com', 'central')).toHaveLength(2);
    expect(filtrar(lista, '', 'admin')).toHaveLength(1);
  });

  it('contagem de pessoas e ativas', () => {
    expect(contagem(lista)).toBe('3 pessoas · 2 ativas');
  });

  it('operações', () => {
    expect(operacoesTexto(lista[0])).toBe('Todas');
    expect(operacoesTexto({ ...lista[0], todasOperacoes: false, operacoes: [{ id: '1', nome: 'Ipiranga' }] })).toBe('Ipiranga');
  });

  it('aparelho pelo user-agent', () => {
    expect(aparelho('Mozilla/5.0 (Windows NT 10.0) AppleWebKit Chrome/131 Safari/537')).toBe('Chrome · Windows');
    expect(aparelho(null)).toBe('Navegador desconhecido');
  });

  it('mensagens de erro conhecidas e genérica', () => {
    expect(mensagemAdmin('EMAIL_JA_CADASTRADO')).toBe('Este e-mail já está cadastrado.');
    expect(mensagemAdmin('XYZ')).toContain('Tente de novo');
  });
});
