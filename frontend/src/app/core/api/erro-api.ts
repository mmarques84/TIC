import { HttpErrorResponse } from '@angular/common/http';

// Erro de regra vem do banco como código em maiúsculas (ex.: CREDENCIAIS_INVALIDAS) e o n8n repassa em { codigo }.
export interface ErroApi {
  status: number;
  codigo: string;
  semSessao: boolean;
  semPermissao: boolean;
  semConexao: boolean;
}

export function paraErroApi(e: unknown): ErroApi {
  if (e instanceof HttpErrorResponse) {
    const codigo = typeof e.error?.codigo === 'string' ? e.error.codigo : `HTTP_${e.status}`;
    return { status: e.status, codigo, semSessao: e.status === 401, semPermissao: e.status === 403, semConexao: e.status === 0 };
  }
  if (e instanceof ErroRegra) {
    return { status: e.status, codigo: e.codigo, semSessao: e.status === 401, semPermissao: e.status === 403, semConexao: false };
  }
  return { status: 0, codigo: 'DESCONHECIDO', semSessao: false, semPermissao: false, semConexao: true };
}

/** Erro de regra usado pela camada de dados fictícia (mesmo formato que a API real devolve). */
export class ErroRegra extends Error {
  constructor(
    readonly codigo: string,
    readonly status = 400,
  ) {
    super(codigo);
  }
}
