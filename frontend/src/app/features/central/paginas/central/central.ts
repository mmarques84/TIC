import { Component, OnInit, computed, effect, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { Sessao } from '../../../../core/auth/sessao';
import { CentralStore } from '../../estado/central.store';
import {
  MOTIVOS_FALSO, NOME_ACAO, NOME_CAMERA, NOME_ESTADO, NOME_ESTADO_ACAO, NOME_NIVEL, TIPOS, haQuanto, hora, situacao, textoIA,
} from '../../dominio/central';

@Component({
  selector: 'tic-central',
  imports: [RouterLink],
  providers: [CentralStore],
  templateUrl: './central.html',
  styleUrl: './central.scss',
})
export class Central implements OnInit {
  readonly store = inject(CentralStore);
  private readonly sessao = inject(Sessao);

  readonly nomeNivel = NOME_NIVEL;
  readonly nomeCamera = NOME_CAMERA;
  readonly nomeAcao = NOME_ACAO;
  readonly nomeEstadoAcao = NOME_ESTADO_ACAO;
  readonly nomeEstado = NOME_ESTADO;
  readonly tipos = TIPOS;
  readonly motivos = MOTIVOS_FALSO;
  readonly textoIA = textoIA;
  readonly situacao = situacao;
  readonly hora = hora;

  readonly podeTratar = computed(() => this.sessao.pode('alerta.tratar'));
  readonly podeAcionar = computed(() => this.sessao.pode('alerta.acionar'));
  readonly eu = computed(() => this.sessao.usuario()?.nome ?? '');

  readonly textoMensagem = signal('');
  readonly motivo = signal('');
  readonly observacao = signal('');

  constructor() {
    // Texto pronto da mensagem quando abre outro alerta.
    effect(() => this.textoMensagem.set(this.store.detalhe()?.mensagemPadrao ?? ''));
  }

  ngOnInit(): void {
    this.store.iniciar();
  }

  ha(iso: string | null): string {
    return haQuanto(iso, this.store.agora());
  }

  v(ev: Event): string {
    return (ev.target as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement).value;
  }

  abrirFalso(): void {
    this.motivo.set('');
    this.observacao.set('');
    this.store.erro.set('');
    this.store.modal.set('falso');
  }

  abrirConfirmar(): void {
    this.observacao.set('');
    this.store.erro.set('');
    this.store.modal.set('confirmar');
  }
}
