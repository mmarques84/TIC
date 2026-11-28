import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { DetalheConducao, FiltrosConducao, FiltrosRanking, PaginaConducao, RankingConducao, VisaoConducao } from '../dominio/conducao';

@Injectable({ providedIn: 'root' })
export class ConducaoApi {
  private readonly http = inject(HttpClient);

  listar(filtros: FiltrosConducao, cursor: string) {
    return this.http.get<PaginaConducao>('/api/conducao/eventos', { params: { ...filtros, cursor } });
  }

  ranking(f: FiltrosRanking) {
    return this.http.get<RankingConducao>('/api/conducao/ranking', { params: { ...f } });
  }

  detalhe(periodo: string, visao: VisaoConducao, chave: string) {
    return this.http.get<DetalheConducao>('/api/conducao/detalhe', { params: { periodo, visao, chave } });
  }

  /** Mesmo ranking, com registro na auditoria (R13). */
  exportar(f: FiltrosRanking) {
    return this.http.get<RankingConducao>('/api/conducao/exportar', { params: { ...f } });
  }
}
