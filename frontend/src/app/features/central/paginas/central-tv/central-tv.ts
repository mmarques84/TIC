import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';

import { Logo } from '../../../../ui/logo/logo';
import { CentralStore } from '../../estado/central.store';
import { NOME_NIVEL, hora, minutosDesde, semAtualizacao, situacao } from '../../dominio/central';

// R19, R20: a Central na TV da parede. Sem botões, sem fotos de pessoas.
@Component({
  selector: 'tic-central-tv',
  imports: [Logo],
  providers: [CentralStore],
  templateUrl: './central-tv.html',
  styleUrl: './central-tv.scss',
})
export class CentralTv implements OnInit, OnDestroy {
  readonly store = inject(CentralStore);
  readonly nomeNivel = NOME_NIVEL;
  readonly situacao = situacao;
  readonly hora = hora;

  private relogio: ReturnType<typeof setInterval> | null = null;
  readonly agora = signal(new Date());
  readonly parada = computed(() => !this.store.carregando() && semAtualizacao(this.store.ultimaOk(), this.agora()));
  readonly relogioTexto = computed(() => this.agora().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }));

  ngOnInit(): void {
    this.store.iniciar(false);
    this.relogio = setInterval(() => this.agora.set(new Date()), 1000);
  }

  ngOnDestroy(): void {
    if (this.relogio) clearInterval(this.relogio);
  }

  ha(iso: string | null): string {
    return minutosDesde(iso, this.agora());
  }
}
