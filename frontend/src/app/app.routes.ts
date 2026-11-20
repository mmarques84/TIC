import { Routes } from '@angular/router';

import { anonimoGuard, autenticadoGuard, permissaoGuard } from './core/auth/guardas';
import { ITENS_COM_ROTA } from './core/navegacao/navegacao';

const emConstrucao = () => import('./features/em-construcao/em-construcao').then((m) => m.EmConstrucao);

export const routes: Routes = [
  {
    path: 'login',
    canActivate: [anonimoGuard],
    title: 'Entrar · TIC Painel Digital',
    loadComponent: () => import('./features/acesso/paginas/login/login').then((m) => m.Login),
  },
  {
    path: 'esqueci-senha',
    canActivate: [anonimoGuard],
    title: 'Esqueci a senha · TIC Painel Digital',
    loadComponent: () => import('./features/acesso/paginas/esqueci-senha/esqueci-senha').then((m) => m.EsqueciSenha),
  },
  {
    path: 'definir-senha',
    title: 'Criar senha · TIC Painel Digital',
    loadComponent: () => import('./features/acesso/paginas/definir-senha/definir-senha').then((m) => m.DefinirSenha),
  },
  {
    path: '',
    canActivate: [autenticadoGuard],
    loadComponent: () => import('./layout/shell/shell').then((m) => m.Shell),
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'inicio' },
      {
        path: 'inicio',
        title: 'Início · TIC Painel Digital',
        loadComponent: () => import('./features/inicio/paginas/inicio/inicio').then((m) => m.Inicio),
      },
      ...ITENS_COM_ROTA.map((item) => ({
        path: item.rota.slice(1),
        canActivate: [permissaoGuard(item.permissao!)],
        title: `${item.rotulo} · TIC Painel Digital`,
        data: { titulo: item.rotulo },
        loadComponent: emConstrucao,
      })),
      { path: 'sem-acesso', title: 'Sem acesso', loadComponent: () => import('./features/sem-acesso/sem-acesso').then((m) => m.SemAcesso) },
    ],
  },
  { path: '**', redirectTo: '' },
];
