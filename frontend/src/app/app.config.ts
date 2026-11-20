import { provideHttpClient, withFetch, withInterceptors, withXsrfConfiguration } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withComponentInputBinding } from '@angular/router';

import { routes } from './app.routes';
import { DADOS_FICTICIOS } from './core/config';
import { AuthApi, AuthApiFicticia, AuthApiHttp } from './core/auth/dados/auth-api';
import { sessaoInterceptor } from './core/auth/sessao-interceptor';
import { InicioApi, InicioApiFicticia, InicioApiHttp } from './features/inicio/dados/inicio-api';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes, withComponentInputBinding()),
    provideHttpClient(
      withFetch(),
      withInterceptors([sessaoInterceptor]),
      withXsrfConfiguration({ cookieName: 'XSRF-TOKEN', headerName: 'X-XSRF-TOKEN' }),
    ),
    // Adaptadores de dados: trocar a implementação não mexe em nenhuma tela.
    { provide: AuthApi, useClass: DADOS_FICTICIOS.auth ? AuthApiFicticia : AuthApiHttp },
    { provide: InicioApi, useClass: DADOS_FICTICIOS.inicio ? InicioApiFicticia : InicioApiHttp },
  ],
};
