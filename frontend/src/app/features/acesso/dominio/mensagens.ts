import { ErroApi } from '../../../core/api/erro-api';

// Texto para a pessoa a partir do código de erro do backend. Nunca revela se o e-mail existe.
export function mensagemDeErro(e: ErroApi): string {
  if (e.semConexao) return 'Sem conexão com o servidor. Confira a internet e tente de novo.';
  switch (e.codigo) {
    case 'CREDENCIAIS_INVALIDAS':
      return 'E-mail ou senha incorretos.';
    case 'BLOQUEADO':
      return 'Muitas tentativas. O acesso fica bloqueado por 15 minutos.';
    case 'USUARIO_INATIVO':
      return 'Acesso desativado. Fale com o administrador do portal.';
    case 'LINK_INVALIDO':
    case 'LINK_VENCIDO':
      return 'Este link não vale mais. Peça um novo ao administrador.';
    case 'SENHA_FRACA':
      return 'A senha não atende às regras.';
    default:
      return 'Não foi possível concluir agora. Tente de novo em alguns segundos.';
  }
}
