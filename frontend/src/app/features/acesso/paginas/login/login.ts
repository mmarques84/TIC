import { Component, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { paraErroApi } from '../../../../core/api/erro-api';
import { USAR_DADOS_FICTICIOS } from '../../../../core/config';
import { SENHA_FICTICIA } from '../../../../core/auth/dados/auth-api';
import { Sessao } from '../../../../core/auth/sessao';
import { PainelAcesso } from '../../componentes/painel-acesso/painel-acesso';
import { mensagemDeErro } from '../../dominio/mensagens';

@Component({
  selector: 'tic-login',
  imports: [RouterLink, PainelAcesso],
  templateUrl: './login.html',
  styleUrl: '../acesso.scss',
})
export class Login {
  private readonly sessao = inject(Sessao);
  private readonly router = inject(Router);

  /** Para onde voltar depois do login (só caminhos internos). */
  readonly voltar = input<string>();

  readonly email = signal('');
  readonly senha = signal('');
  readonly mostrar = signal(false);
  readonly enviando = signal(false);
  readonly erro = signal('');
  readonly ficticio = USAR_DADOS_FICTICIOS;
  readonly senhaFicticia = SENHA_FICTICIA;

  async entrar(ev: Event): Promise<void> {
    ev.preventDefault();
    if (this.enviando()) return;
    if (!this.email().trim() || !this.senha()) {
      this.erro.set('Preencha o e-mail e a senha.');
      return;
    }
    this.enviando.set(true);
    this.erro.set('');
    try {
      await this.sessao.entrar(this.email(), this.senha());
      const destino = this.voltar();
      await this.router.navigateByUrl(destino?.startsWith('/') && !destino.startsWith('//') ? destino : '/inicio');
    } catch (e) {
      this.erro.set(mensagemDeErro(paraErroApi(e)));
      this.senha.set('');
    } finally {
      this.enviando.set(false);
    }
  }

  valor(ev: Event): string {
    return (ev.target as HTMLInputElement).value;
  }
}
