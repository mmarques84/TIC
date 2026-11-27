// Regras de senha mostradas na tela de definição (o servidor valida de novo).

export const SENHA_MIN = 8;

const COMUNS = ['123456789012', 'senhasenha12', 'tictransportes', 'qwertyuiop12', 'abcdefghijkl'];

export interface ChecagemSenha {
  tamanho: boolean;
  naoComum: boolean;
  iguais: boolean;
  valida: boolean;
}

// Mesma regra do servidor (n8n/codigo/senha.js): não pode conter o começo do e-mail nem nenhuma palavra do nome (3+ letras).
const norm = (t: string) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

export function checarSenha(senha: string, confirmacao: string, email: string, nome = ''): ChecagemSenha {
  const s = norm(senha);
  const pedacos = [norm(email.split('@')[0] ?? ''), ...norm(nome).split(/\s+/)].filter((p) => p.length >= 3);
  const tamanho = senha.length >= SENHA_MIN;
  const naoComum = senha.length > 0 && !COMUNS.some((c) => s.includes(c)) && !pedacos.some((p) => s.includes(p));
  const iguais = senha.length > 0 && senha === confirmacao;
  return { tamanho, naoComum, iguais, valida: tamanho && naoComum && iguais };
}
