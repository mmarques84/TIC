import { Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter, map } from 'rxjs';

import { NOME_PERFIL } from '../../core/auth/dominio/usuario';
import { Sessao } from '../../core/auth/sessao';
import { menuDoUsuario } from '../../core/navegacao/navegacao';
import { Logo } from '../../ui/logo/logo';

const CHAVE_GRUPOS = 'tic.menu.abertos';

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

  // Grupos recolhíveis: o que a pessoa abriu fica guardado neste navegador; o grupo da tela atual sempre aparece aberto.
  private readonly abertosSalvos = signal<Set<string>>(lerAbertos());
  private readonly url = toSignal(
    this.router.events.pipe(filter((e) => e instanceof NavigationEnd), map(() => this.router.url)),
    { initialValue: this.router.url },
  );
  private readonly grupoAtual = computed(() => {
    const u = this.url();
    return this.grupos().find((g) => g.itens.some((i) => !i.emBreve && u.startsWith(i.rota)))?.nome ?? null;
  });

  /** Aberto se a pessoa abriu, ou se é o grupo da tela atual e ela não o fechou ("!nome"). */
  aberto(nome: string): boolean {
    const s = this.abertosSalvos();
    if (s.has(`!${nome}`)) return false;
    return s.has(nome) || this.grupoAtual() === nome;
  }

  alternar(nome: string): void {
    const s = new Set(this.abertosSalvos());
    if (this.aberto(nome)) {
      s.delete(nome);
      if (this.grupoAtual() === nome) s.add(`!${nome}`);
    } else {
      s.add(nome);
      s.delete(`!${nome}`);
    }
    this.abertosSalvos.set(s);
    gravarAbertos(s);
  }

  async sair(): Promise<void> {
    await this.sessao.sair();
    await this.router.navigate(['/login']);
  }
}

function lerAbertos(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(CHAVE_GRUPOS) ?? '[]') as string[]);
  } catch {
    return new Set();
  }
}

function gravarAbertos(s: Set<string>): void {
  try {
    localStorage.setItem(CHAVE_GRUPOS, JSON.stringify([...s]));
  } catch {
    /* navegação privada */
  }
}
