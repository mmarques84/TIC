import { DestroyRef, Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../core/api/erro-api';
import { FiltroJornada, JornadaApi } from '../dados/jornada-api';
import { DetalheMotorista, MotoristaJornada, ResumoJornada, mensagemJornada, tratativaValida } from '../dominio/jornada';

const INTERVALO_MS = 60000; // R13: a cada 60 s

// Estado da tela de Jornada. A página só lê signals e chama ações daqui.
@Injectable()
export class JornadaStore {
  private readonly api = inject(JornadaApi);
  private timer: ReturnType<typeof setInterval> | null = null;

  readonly filtro = signal<FiltroJornada>({ faixa: '', dias: '', q: '', semControle: false });
  readonly lista = signal<MotoristaJornada[]>([]);
  readonly resumo = signal<ResumoJornada | null>(null);
  readonly carregando = signal(true);
  readonly erroLista = signal('');
  readonly abertoId = signal<string | null>(null);
  readonly detalhe = signal<DetalheMotorista | null>(null);
  readonly carregandoDetalhe = signal(false);
  readonly ocupado = signal(false);
  readonly erro = signal('');
  readonly aviso = signal('');
  readonly agora = signal(new Date());

  constructor() {
    inject(DestroyRef).onDestroy(() => {
      if (this.timer) clearInterval(this.timer);
    });
  }

  iniciar(): void {
    void this.atualizar();
    this.timer ??= setInterval(() => void this.atualizar(), INTERVALO_MS);
  }

  mudarFiltro(parcial: Partial<FiltroJornada>): void {
    this.filtro.update((f) => ({ ...f, ...parcial }));
    void this.atualizar();
  }

  async atualizar(): Promise<void> {
    try {
      const [lista, resumo] = await Promise.all([firstValueFrom(this.api.listar(this.filtro())), firstValueFrom(this.api.resumo())]);
      this.lista.set(lista);
      this.resumo.set(resumo);
      this.agora.set(new Date());
      this.erroLista.set('');
    } catch (e) {
      if (!this.lista().length) this.erroLista.set(mensagemJornada(paraErroApi(e).codigo));
    } finally {
      this.carregando.set(false);
    }
  }

  async alternar(id: string): Promise<void> {
    if (this.abertoId() === id) {
      this.abertoId.set(null);
      this.detalhe.set(null);
      return;
    }
    this.abertoId.set(id);
    this.detalhe.set(null);
    this.erro.set('');
    this.aviso.set('');
    this.carregandoDetalhe.set(true);
    try {
      this.detalhe.set(await firstValueFrom(this.api.detalhe(id)));
    } catch (e) {
      this.erro.set(mensagemJornada(paraErroApi(e).codigo));
    } finally {
      this.carregandoDetalhe.set(false);
    }
  }

  async tratar(tipo: string, observacao: string, jornada: string | null): Promise<boolean> {
    const id = this.abertoId();
    const invalida = tratativaValida(tipo, observacao);
    if (invalida) {
      this.erro.set(invalida);
      return false;
    }
    if (!id || this.ocupado()) return false;
    this.ocupado.set(true);
    this.erro.set('');
    try {
      const linha = await firstValueFrom(this.api.tratativa(id, jornada, tipo, observacao));
      this.lista.update((l) => l.map((m) => (m.id === id ? linha : m)));
      this.detalhe.set(await firstValueFrom(this.api.detalhe(id)));
      this.aviso.set('Tratativa registrada.');
      void this.atualizar();
      return true;
    } catch (e) {
      this.erro.set(mensagemJornada(paraErroApi(e).codigo));
      return false;
    } finally {
      this.ocupado.set(false);
    }
  }
}
