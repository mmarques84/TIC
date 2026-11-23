import { DestroyRef, Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../core/api/erro-api';
import { CentralApi, FiltroCentral } from '../dados/central-api';
import { AlertaDetalhe, AlertaFila, ResumoCentral, criticosNovos, mensagemCentral } from '../dominio/central';

const INTERVALO_MS = 5000; // R6: atualiza a cada 5 s

export type ModalCentral = '' | 'sirene' | 'falso' | 'confirmar';

// Estado da Central. A página só lê signals e chama ações daqui.
@Injectable()
export class CentralStore {
  private readonly api = inject(CentralApi);
  private timer: ReturnType<typeof setInterval> | null = null;
  private vistos: Set<string> | null = null;

  readonly filtro = signal<FiltroCentral>({ aba: 'abertos', nivel: '', tipo: '', q: '' });
  readonly fila = signal<AlertaFila[]>([]);
  readonly resumo = signal<ResumoCentral | null>(null);
  readonly ultimaOk = signal<Date | null>(null);
  readonly erroFila = signal('');
  readonly carregando = signal(true);
  readonly selecionadoId = signal<string | null>(null);
  readonly detalhe = signal<AlertaDetalhe | null>(null);
  readonly carregandoDetalhe = signal(false);
  readonly modal = signal<ModalCentral>('');
  readonly editandoMensagem = signal(false);
  readonly ocupado = signal(false);
  readonly erro = signal('');
  readonly aviso = signal('');
  readonly som = signal(false);
  readonly destaque = signal<Set<string>>(new Set());

  readonly agora = signal(new Date());
  readonly temSelecionado = computed(() => !!this.selecionadoId());

  constructor() {
    inject(DestroyRef).onDestroy(() => this.parar());
  }

  iniciar(comDetalhe = true): void {
    void this.atualizar(comDetalhe);
    this.timer ??= setInterval(() => void this.atualizar(comDetalhe), INTERVALO_MS);
  }

  parar(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  mudarFiltro(parcial: Partial<FiltroCentral>): void {
    this.filtro.update((f) => ({ ...f, ...parcial }));
    void this.atualizar(true);
  }

  async atualizar(comDetalhe: boolean): Promise<void> {
    try {
      const [fila, resumo] = await Promise.all([firstValueFrom(this.api.listar(this.filtro())), firstValueFrom(this.api.resumo())]);
      this.agora.set(new Date());
      if (this.filtro().aba === 'abertos') {
        const novos = criticosNovos(this.vistos, fila);
        if (novos.length) {
          this.destaque.set(new Set(novos));
          if (this.som()) tocarAviso();
        }
        this.vistos = new Set(fila.filter((a) => a.nivel === 'critico').map((a) => a.id));
      }
      this.fila.set(fila);
      this.resumo.set(resumo);
      this.ultimaOk.set(new Date());
      this.erroFila.set('');
      if (comDetalhe && !this.selecionadoId() && fila.length) await this.abrir(fila[0].id);
    } catch (e) {
      this.agora.set(new Date());
      if (!this.fila().length) this.erroFila.set(mensagemCentral(paraErroApi(e).codigo));
    } finally {
      this.carregando.set(false);
    }
  }

  async abrir(id: string): Promise<void> {
    this.selecionadoId.set(id);
    this.editandoMensagem.set(false);
    this.erro.set('');
    this.aviso.set('');
    this.carregandoDetalhe.set(true);
    try {
      this.detalhe.set(await firstValueFrom(this.api.detalhe(id)));
    } catch (e) {
      this.detalhe.set(null);
      this.erro.set(mensagemCentral(paraErroApi(e).codigo));
    } finally {
      this.carregandoDetalhe.set(false);
    }
  }

  assumir(): Promise<void> {
    return this.agir((id) => this.api.assumir(id), 'Você assumiu este alerta.');
  }
  mensagem(texto: string): Promise<void> {
    return this.agir((id) => this.api.mensagem(id, texto), 'Mensagem na fila de envio ao terminal.', () => this.editandoMensagem.set(false));
  }
  sirene(): Promise<void> {
    return this.agir((id) => this.api.sirene(id), 'Sirene na fila de envio.', () => this.modal.set(''));
  }
  confirmar(observacao: string): Promise<void> {
    return this.agir((id) => this.api.confirmar(id, observacao), 'Alerta confirmado.', () => this.saiuDaFila());
  }
  falso(motivo: string, observacao: string): Promise<void> {
    if (!motivo) {
      this.erro.set(mensagemCentral('MOTIVO_OBRIGATORIO'));
      return Promise.resolve();
    }
    return this.agir((id) => this.api.falso(id, motivo, observacao), 'Marcado como falso positivo.', () => this.saiuDaFila());
  }

  alternarSom(): void {
    this.som.update((s) => !s);
  }

  private saiuDaFila(): void {
    this.modal.set('');
    const resto = this.fila().filter((a) => a.id !== this.selecionadoId());
    this.fila.set(resto);
    this.selecionadoId.set(null);
    this.detalhe.set(null);
    if (resto.length) void this.abrir(resto[0].id);
  }

  private async agir(chamada: (id: string) => ReturnType<CentralApi['assumir']>, ok: string, depois?: () => void): Promise<void> {
    const id = this.selecionadoId();
    if (!id || this.ocupado()) return;
    this.ocupado.set(true);
    this.erro.set('');
    try {
      await firstValueFrom(chamada(id));
      this.aviso.set(ok);
      depois?.();
      if (this.selecionadoId() === id) this.detalhe.set(await firstValueFrom(this.api.detalhe(id)));
      void this.atualizar(false);
    } catch (e) {
      const codigo = paraErroApi(e).codigo;
      this.erro.set(mensagemCentral(codigo));
      if (codigo === 'ALERTA_JA_TRATADO') this.saiuDaFila();
    } finally {
      this.ocupado.set(false);
    }
  }
}

/** Bip curto (Web Audio): só depois que a pessoa ligou o som (o navegador exige um clique antes). */
function tocarAviso(): void {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const ganho = ctx.createGain();
    osc.frequency.value = 880;
    ganho.gain.value = 0.15;
    osc.connect(ganho).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.35);
  } catch {
    /* sem áudio */
  }
}
