import { Component, input } from '@angular/core';

import { Logo } from '../../../../ui/logo/logo';

// Moldura das telas sem login: painel da marca à esquerda, formulário (conteúdo projetado) à direita.
@Component({
  selector: 'tic-painel-acesso',
  imports: [Logo],
  template: `
    <div class="tela">
      <section class="marca" aria-label="Sobre o portal">
        <div class="topo">
          <tic-logo />
          <span class="divisor" aria-hidden="true"></span>
          <span class="nome">Painel Digital</span>
        </div>
        <div class="chamada">
          <span class="traco" aria-hidden="true"></span>
          <h1>{{ titulo() }}</h1>
          <p>{{ subtitulo() }}</p>
        </div>
        <p class="assinatura">TIC Transportes · desenvolvido por MX Midas</p>
      </section>
      <main class="lado">
        <div class="cartao">
          <ng-content />
        </div>
      </main>
    </div>
  `,
  styleUrl: './painel-acesso.scss',
})
export class PainelAcesso {
  readonly titulo = input('Alertas, jornada e OPI num lugar só.');
  readonly subtitulo = input('Câmeras, telemetria e jornada da frota reunidas, com triagem por IA e histórico de 12 meses.');
}
