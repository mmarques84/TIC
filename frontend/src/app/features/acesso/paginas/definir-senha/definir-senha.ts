import { Component, OnInit, computed, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../../core/api/erro-api';
import { AuthApi } from '../../../../core/auth/dados/auth-api';
import { checarSenha, SENHA_MIN } from '../../../../core/auth/dominio/senha';
import { NOME_PERFIL, Perfil } from '../../../../core/auth/dominio/usuario';
import { Sessao } from '../../../../core/auth/sessao';
import { PainelAcesso } from '../../componentes/painel-acesso/painel-acesso';
import { mensagemDeErro } from '../../dominio/mensagens';

@Component({
  selector: 'tic-definir-senha',
  imports: [RouterLink, PainelAcesso],
  template: `
    <tic-painel-acesso titulo="Bem-vindo ao Painel Digital." subtitulo="Seu acesso foi criado pelo administrador. Defina uma senha para entrar.">
      @if (carregando()) {
        <p class="texto" role="status">Conferindo o link…</p>
      } @else if (linkInvalido()) {
        <div class="form">
          <div class="cabeca"><h2>Link inválido</h2></div>
          <div class="tic-aviso erro" role="alert">{{ linkInvalido() }}</div>
          <a class="tic-botao" routerLink="/login">Ir para o login</a>
        </div>
      } @else {
        <form class="form" (submit)="salvar($event)" novalidate>
          <div class="cabeca">
            <h2>Criar sua senha</h2>
            <p>Acesso de <strong>{{ email() }}</strong> · perfil {{ perfil() }}</p>
          </div>
          @if (erro()) {
            <div class="tic-aviso erro" role="alert">{{ erro() }}</div>
          }
          <div class="tic-campo">
            <label for="nova">Nova senha</label>
            <input id="nova" type="password" autocomplete="new-password" aria-describedby="regras"
                   [value]="senha()" (input)="senha.set($any($event.target).value)" />
          </div>
          <ul id="regras" class="regras" aria-live="polite">
            <li [class.ok]="checagem().tamanho">{{ checagem().tamanho ? '✓' : '○' }} Pelo menos {{ min }} caracteres</li>
            <li [class.ok]="checagem().naoComum">{{ checagem().naoComum ? '✓' : '○' }} Não é uma senha comum nem contém seu e-mail</li>
            <li [class.ok]="checagem().iguais">{{ checagem().iguais ? '✓' : '○' }} As duas senhas são iguais</li>
          </ul>
          <div class="tic-campo">
            <label for="conf">Repita a senha</label>
            <input id="conf" type="password" autocomplete="new-password"
                   [value]="confirmacao()" (input)="confirmacao.set($any($event.target).value)" />
          </div>
          <button type="submit" class="tic-botao" [disabled]="enviando()">{{ enviando() ? 'Salvando…' : 'Salvar e entrar' }}</button>
          <p class="texto" style="font-size: 13px">Este link vale até {{ expira() }} e só pode ser usado uma vez.</p>
        </form>
      }
    </tic-painel-acesso>
  `,
  styleUrl: '../acesso.scss',
})
export class DefinirSenha implements OnInit {
  private readonly api = inject(AuthApi);
  private readonly sessao = inject(Sessao);
  private readonly router = inject(Router);

  readonly token = input<string>('');
  readonly min = SENHA_MIN;
  readonly carregando = signal(true);
  readonly linkInvalido = signal('');
  readonly email = signal('');
  readonly perfil = signal('');
  readonly expira = signal('');
  readonly senha = signal('');
  readonly confirmacao = signal('');
  readonly enviando = signal(false);
  readonly erro = signal('');
  readonly checagem = computed(() => checarSenha(this.senha(), this.confirmacao(), this.email()));

  async ngOnInit(): Promise<void> {
    try {
      const l = await firstValueFrom(this.api.consultarLink(this.token()));
      this.email.set(l.email);
      this.perfil.set(NOME_PERFIL[l.perfil as Perfil] ?? l.perfil);
      this.expira.set(new Date(l.expiraEm).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }));
    } catch (e) {
      this.linkInvalido.set(mensagemDeErro(paraErroApi(e)));
    } finally {
      this.carregando.set(false);
    }
  }

  async salvar(ev: Event): Promise<void> {
    ev.preventDefault();
    if (!this.checagem().valida) {
      this.erro.set('A senha ainda não atende a todas as regras.');
      return;
    }
    this.enviando.set(true);
    this.erro.set('');
    try {
      await this.sessao.definirSenha(this.token(), this.senha());
      await this.router.navigateByUrl('/inicio');
    } catch (e) {
      this.erro.set(mensagemDeErro(paraErroApi(e)));
    } finally {
      this.enviando.set(false);
    }
  }
}
