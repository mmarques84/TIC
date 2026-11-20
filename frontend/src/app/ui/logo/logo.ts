import { Component, input } from '@angular/core';

// Espaço reservado até chegar o arquivo do logo da TIC.
@Component({
  selector: 'tic-logo',
  template: `<span class="logo" [class.p]="tamanho() === 'p'" role="img" aria-label="TIC Transportes">Logo TIC</span>`,
  styles: `
    .logo {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 120px;
      height: 48px;
      border: 1.5px dashed var(--tic-marinho-texto-apagado);
      border-radius: var(--tic-raio-p);
      font-size: 13px;
      color: var(--tic-marinho-texto-suave);
      flex: none;
    }
    .p {
      width: 76px;
      height: 34px;
      font-size: 12px;
    }
  `,
})
export class Logo {
  readonly tamanho = input<'p' | 'g'>('g');
}
