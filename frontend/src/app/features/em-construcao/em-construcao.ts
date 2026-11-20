import { Component, input } from '@angular/core';
import { RouterLink } from '@angular/router';

// Tela de item do menu que ainda não tem layout aprovado nem spec implementada.
@Component({
  selector: 'tic-em-construcao',
  imports: [RouterLink],
  template: `
    <section class="tic-cartao caixa">
      <h1>{{ titulo() }}</h1>
      <p>Esta tela ainda está em construção. Ela entra depois da spec e do layout aprovados.</p>
      <a routerLink="/inicio">Voltar ao início</a>
    </section>
  `,
  styles: `
    .caixa { padding: 32px; max-width: 640px; display: flex; flex-direction: column; gap: 12px; }
    h1 { margin: 0; font-size: 24px; color: var(--tic-marinho); }
    p { margin: 0; color: var(--tic-texto-secundario); }
  `,
})
export class EmConstrucao {
  readonly titulo = input('Em construção');
}
