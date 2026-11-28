import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ConducaoApi } from '../dados/conducao-api';
import { DetalheConducao, FiltrosRanking, RankingConducao, csvRanking } from '../dominio/conducao';

const NOME_PERIODO: Record<string, string> = { hoje: 'hoje', '7': 'últimos 7 dias', mes: 'mês atual', anterior: 'mês anterior' };

@Injectable()
export class RankingStore {
  private readonly api = inject(ConducaoApi);
  readonly filtros = signal<FiltrosRanking>({ periodo: '7', visao: 'motorista', tipo: '', q: '' });
  readonly dados = signal<RankingConducao | null>(null);
  readonly carregando = signal(false);
  readonly erro = signal('');
  readonly aberta = signal<string | null>(null);
  readonly detalhe = signal<DetalheConducao | null>(null);
  readonly carregandoDetalhe = signal(false);
  readonly exportando = signal(false);

  mudar(parcial: Partial<FiltrosRanking>) {
    this.filtros.update((f) => ({ ...f, ...parcial }));
    this.aberta.set(null);
    return this.carregar();
  }

  async carregar() {
    this.carregando.set(true);
    this.erro.set('');
    try {
      this.dados.set(await firstValueFrom(this.api.ranking(this.filtros())));
    } catch {
      this.dados.set(null);
      this.erro.set('Não foi possível carregar o ranking.');
    } finally {
      this.carregando.set(false);
    }
  }

  async abrir(chave: string) {
    if (this.aberta() === chave) { this.aberta.set(null); return; }
    this.aberta.set(chave);
    this.detalhe.set(null);
    this.carregandoDetalhe.set(true);
    try {
      const f = this.filtros();
      this.detalhe.set(await firstValueFrom(this.api.detalhe(f.periodo, f.visao, chave)));
    } catch {
      this.detalhe.set(null);
    } finally {
      this.carregandoDetalhe.set(false);
    }
  }

  /** R13: baixa o CSV do que está na tela (o servidor registra a exportação). */
  async exportar() {
    this.exportando.set(true);
    try {
      const f = this.filtros();
      const r = await firstValueFrom(this.api.exportar(f));
      const blob = new Blob([csvRanking(r, NOME_PERIODO[f.periodo] ?? f.periodo)], { type: 'text/csv;charset=utf-8' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `conducao-por-${f.visao}-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch {
      this.erro.set('Não foi possível gerar a planilha.');
    } finally {
      this.exportando.set(false);
    }
  }
}
