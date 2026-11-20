import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../api/erro-api';
import { AuthApi } from './dados/auth-api';
import { Permissao, Usuario, pode } from './dominio/usuario';

export type EstadoSessao = 'verificando' | 'autenticado' | 'anonimo';

// Estado da sessão em signals: fonte única para guardas, menu e telas.
// A sessão real mora no servidor (cookie HttpOnly); aqui só fica quem é a pessoa e o que pode.
@Injectable({ providedIn: 'root' })
export class Sessao {
  private readonly api = inject(AuthApi);
  private readonly _usuario = signal<Usuario | null>(null);
  private readonly _estado = signal<EstadoSessao>('verificando');
  private carregando: Promise<Usuario | null> | null = null;

  readonly usuario = this._usuario.asReadonly();
  readonly estado = this._estado.asReadonly();
  readonly autenticado = computed(() => this._estado() === 'autenticado');

  garantir(): Promise<Usuario | null> {
    if (this._estado() !== 'verificando') return Promise.resolve(this._usuario());
    this.carregando ??= firstValueFrom(this.api.me())
      .then((u) => this.definir(u))
      .catch((e) => {
        if (paraErroApi(e).semSessao) return this.definir(null);
        this.carregando = null;
        throw e;
      });
    return this.carregando;
  }

  async entrar(email: string, senha: string): Promise<Usuario> {
    const u = await firstValueFrom(this.api.login(email.trim().toLowerCase(), senha));
    return this.definir(u)!;
  }

  async definirSenha(token: string, senha: string): Promise<Usuario> {
    const u = await firstValueFrom(this.api.definirSenha(token, senha));
    return this.definir(u)!;
  }

  async sair(): Promise<void> {
    try {
      await firstValueFrom(this.api.logout());
    } finally {
      this.definir(null);
    }
  }

  expirou(): void {
    this.definir(null);
  }

  pode(permissao: Permissao): boolean {
    return pode(this._usuario(), permissao);
  }

  private definir(u: Usuario | null): Usuario | null {
    this._usuario.set(u);
    this._estado.set(u ? 'autenticado' : 'anonimo');
    this.carregando = null;
    return u;
  }
}
