import { describe, expect, it } from 'vitest';

import { checarSenha } from './senha';
import { Usuario, pode, primeiroNome } from './usuario';

const u: Usuario = {
  id: '1',
  nome: 'Rafael Exemplo',
  email: 'rafael@exemplo.com',
  perfil: 'operacao',
  permissoes: ['alerta.ver', 'jornada.ver'],
  operacoes: [],
  todasOperacoes: true,
};

describe('domínio de acesso', () => {
  it('pode() só libera permissão que o perfil tem', () => {
    expect(pode(u, 'jornada.ver')).toBe(true);
    expect(pode(u, 'usuario.gerir')).toBe(false);
    expect(pode(null, 'alerta.ver')).toBe(false);
  });

  it('primeiroNome()', () => {
    expect(primeiroNome(u)).toBe('Rafael');
  });

  it('senha: tamanho, comum, e-mail e confirmação', () => {
    expect(checarSenha('curta', 'curta', 'a@b.com').valida).toBe(false);
    expect(checarSenha('rafael-123456', 'rafael-123456', 'rafael@b.com').naoComum).toBe(false);
    expect(checarSenha('frota-segura-2026', 'outra', 'n@b.com').iguais).toBe(false);
    expect(checarSenha('frota-segura-2026', 'frota-segura-2026', 'n@b.com').valida).toBe(true);
    // nome entra na regra, como no servidor (caso real: "Administrador TIC" com senha tic@2027)
    expect(checarSenha('tic@2027', 'tic@2027', 'admin@tic.com.br', 'Administrador TIC').naoComum).toBe(false);
    expect(checarSenha('tic@2027', 'tic@2027', 'admin@tic.com.br', 'Administrador').valida).toBe(true);
    expect(checarSenha('joao#2027x', 'joao#2027x', 'j@b.com', 'João Silva').naoComum).toBe(false);
  });
});
