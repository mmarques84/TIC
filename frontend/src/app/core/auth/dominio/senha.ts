// Regras de senha mostradas na tela de definição (o servidor valida de novo).

export const SENHA_MIN = 8;

const COMUNS = ['123456789012', 'senhasenha12', 'tictransportes', 'qwertyuiop12', 'abcdefghijkl'];

export interface ChecagemSenha {
  tamanho: boolean;
  naoComum: boolean;
  iguais: boolean;
  valida: boolean;
}

export function checarSenha(senha: string, confirmacao: string, email: string): ChecagemSenha {
  const s = senha.toLowerCase();
  const local = email.split('@')[0]?.toLowerCase() ?? '';
  const tamanho = senha.length >= SENHA_MIN;
  const naoComum = senha.length > 0 && !COMUNS.some((c) => s.includes(c)) && !(local.length >= 3 && s.includes(local));
  const iguais = senha.length > 0 && senha === confirmacao;
  return { tamanho, naoComum, iguais, valida: tamanho && naoComum && iguais };
}
