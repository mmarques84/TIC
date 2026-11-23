import { Type } from '@angular/core';
import { Routes } from '@angular/router';

import { anonimoGuard, autenticadoGuard, permissaoGuard } from './core/auth/guardas';
import { ITENS_COM_ROTA } from './core/navegacao/navegacao';

const emConstrucao = () => import('./features/em-construcao/em-construcao').then((m) => m.EmConstrucao);

const TELAS_PRONTAS: Record<string, () => Promise<Type<unknown>>> = {
  '/admin/usuarios': () => import('./features/admin/paginas/usuarios/usuarios').then((m) => m.AdminUsuarios),
  '/alertas': () => import('./features/central/paginas/central/central').then((m) => m.Central),
};

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
  // Central na TV da parede: tela cheia, fora do menu (spec central-alertas R19).
  {
    path: 'alertas/tv',
    canActivate: [autenticadoGuard, permissaoGuard('alerta.ver')],
    title: 'Central de alertas · TV',
    loadComponent: () => import('./features/central/paginas/central-tv/central-tv').then((m) => m.CentralTv),
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
      // Telas prontas têm componente próprio; as outras abrem "Em construção" até a spec e o layout serem aprovados.
      ...ITENS_COM_ROTA.map((item) => ({
        path: item.rota.slice(1),
        canActivate: [permissaoGuard(item.permissao!)],
        title: `${item.rotulo} · TIC Painel Digital`,
        data: { titulo: item.rotulo },
        loadComponent: TELAS_PRONTAS[item.rota] ?? emConstrucao,
      })),
      { path: 'sem-acesso', title: 'Sem acesso', loadComponent: () => import('./features/sem-acesso/sem-acesso').then((m) => m.SemAcesso) },
    ],
  },
  { path: '**', redirectTo: '' },
];
