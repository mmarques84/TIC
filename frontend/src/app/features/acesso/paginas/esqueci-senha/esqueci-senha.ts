import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../../core/api/erro-api';
import { AuthApi } from '../../../../core/auth/dados/auth-api';
import { PainelAcesso } from '../../componentes/painel-acesso/painel-acesso';
import { mensagemDeErro } from '../../dominio/mensagens';

@Component({
  selector: 'tic-esqueci-senha',
  imports: [RouterLink, PainelAcesso],
  template: `
    <tic-painel-acesso>
      <div class="form">
        <a class="voltar" routerLink="/login">← Voltar para o login</a>
        @if (!enviado()) {
          <form class="form" (submit)="enviar($event)" novalidate>
            <div class="cabeca">
              <h2>Esqueci a senha</h2>
              <p>Informe seu e-mail. Se ele estiver cadastrado, você recebe um link para criar uma senha nova.</p>
            </div>
            @if (erro()) {
              <div class="tic-aviso erro" role="alert">{{ erro() }}</div>
            }
            <div class="tic-campo">
              <label for="email">E-mail</label>
              <input id="email" type="email" autocomplete="username" placeholder="nome@tic.com.br"
                     [value]="email()" (input)="email.set($any($event.target).value)" />
            </div>
            <button type="submit" class="tic-botao" [disabled]="enviando()">{{ enviando() ? 'Enviando…' : 'Enviar link' }}</button>
          </form>
        } @else {
          <div class="form" role="status">
            <div class="cabeca"><h2>Confira seu e-mail</h2></div>
            <p class="texto">Se o e-mail estiver cadastrado, o link chega em alguns minutos. Ele vale por <strong>24 horas</strong> e só pode ser usado uma vez.</p>
            <p class="texto">Não chegou? Veja a caixa de spam ou peça ao administrador do portal.</p>
            <button type="button" class="tic-botao-secundario" (click)="enviado.set(false)">Usar outro e-mail</button>
          </div>
        }
      </div>
    </tic-painel-acesso>
  `,
  styleUrl: '../acesso.scss',
})
export class EsqueciSenha {
  private readonly api = inject(AuthApi);
  readonly email = signal('');
  readonly enviando = signal(false);
  readonly enviado = signal(false);
  readonly erro = signal('');

  async enviar(ev: Event): Promise<void> {
    ev.preventDefault();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email().trim())) {
      this.erro.set('Digite um e-mail válido.');
      return;
    }
    this.enviando.set(true);
    this.erro.set('');
    try {
      await firstValueFrom(this.api.esqueci(this.email().trim().toLowerCase()));
      this.enviado.set(true);
    } catch (e) {
      this.erro.set(mensagemDeErro(paraErroApi(e)));
    } finally {
      this.enviando.set(false);
    }
  }
}
