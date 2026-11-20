import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { Sessao } from './sessao';

/** Qualquer 401 fora do próprio /api/auth: sessão expirou ou foi revogada → volta ao login. */
export const sessaoInterceptor: HttpInterceptorFn = (req, next) => {
  const sessao = inject(Sessao);
  const router = inject(Router);
  return next(req).pipe(
    catchError((e: unknown) => {
      if (e instanceof HttpErrorResponse && e.status === 401 && !req.url.startsWith('/api/auth/')) {
        sessao.expirou();
        void router.navigate(['/login']);
      }
      return throwError(() => e);
    }),
  );
};
