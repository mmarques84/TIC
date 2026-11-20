import { Component, computed, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { NOME_PERFIL } from '../../core/auth/dominio/usuario';
import { Sessao } from '../../core/auth/sessao';
import { menuDoUsuario } from '../../core/navegacao/navegacao';
import { Logo } from '../../ui/logo/logo';

@Component({
  selector: 'tic-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, Logo],
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class Shell {
  private readonly sessao = inject(Sessao);
  private readonly router = inject(Router);

  readonly usuario = this.sessao.usuario;
  readonly perfil = computed(() => {
    const u = this.usuario();
    return u ? NOME_PERFIL[u.perfil] : '';
  });
  readonly grupos = computed(() => (this.usuario() ? menuDoUsuario((p) => this.sessao.pode(p)) : []));

  async sair(): Promise<void> {
    await this.sessao.sair();
    await this.router.navigate(['/login']);
  }
}
