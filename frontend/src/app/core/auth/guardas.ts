import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { Permissao } from './dominio/usuario';
import { Sessao } from './sessao';

/** Só entra logado; senão vai para o login guardando para onde queria ir. */
export const autenticadoGuard: CanActivateFn = async (_r, estado) => {
  const sessao = inject(Sessao);
  const router = inject(Router);
  const u = await sessao.garantir();
  return u ? true : router.createUrlTree(['/login'], { queryParams: estado.url !== '/' ? { voltar: estado.url } : {} });
};

/** Login e "esqueci" não fazem sentido para quem já está logado. */
// Atenção: inject() só funciona antes do primeiro await (contexto de injeção).
export const anonimoGuard: CanActivateFn = async () => {
  const sessao = inject(Sessao);
  const router = inject(Router);
  const u = await sessao.garantir();
  return u ? router.createUrlTree(['/']) : true;
};

export function permissaoGuard(permissao: Permissao): CanActivateFn {
  return async () => {
    const sessao = inject(Sessao);
    const router = inject(Router);
    await sessao.garantir();
    return sessao.pode(permissao) ? true : router.createUrlTree(['/sem-acesso']);
  };
}
