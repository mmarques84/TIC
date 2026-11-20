import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'tic-sem-acesso',
  imports: [RouterLink],
  template: `
    <section class="tic-cartao caixa" role="alert">
      <h1>Sem acesso</h1>
      <p>Seu perfil não pode abrir esta tela. Se precisar, peça ao administrador do portal.</p>
      <a routerLink="/inicio">Voltar ao início</a>
    </section>
  `,
  styles: `
    .caixa { padding: 32px; max-width: 640px; display: flex; flex-direction: column; gap: 12px; }
    h1 { margin: 0; font-size: 24px; color: var(--tic-marinho); }
    p { margin: 0; color: var(--tic-texto-secundario); }
  `,
})
export class SemAcesso {}
