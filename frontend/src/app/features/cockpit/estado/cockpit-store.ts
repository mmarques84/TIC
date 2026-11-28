import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { CockpitApi } from '../dados/cockpit-api';
import { FiltrosCockpit, ResumoCockpit } from '../dominio/cockpit';

@Injectable()
export class CockpitStore {
  private readonly api = inject(CockpitApi);
  private filtros: FiltrosCockpit = { periodo: '7', operacao: '', placa: '', tipo: '' };
  readonly resumo = signal<ResumoCockpit | null>(null);
  readonly recorte = signal(this.filtros);
  readonly carregando = signal(false);
  readonly erro = signal(false);
  readonly maxTipo = computed(() => Math.max(1, ...(this.resumo()?.tipos.map(tipo => tipo.total) ?? [])));

  async consultar(filtros = this.filtros) {
    if (this.carregando()) return;
    this.filtros = filtros;
    this.carregando.set(true);
    this.erro.set(false);
    try {
      this.resumo.set(await firstValueFrom(this.api.consultar(filtros)));
      this.recorte.set(filtros);
    } catch {
      this.erro.set(true);
    } finally {
      this.carregando.set(false);
    }
  }
}
