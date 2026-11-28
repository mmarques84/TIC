import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { FiltrosConducao, PaginaConducao } from '../dominio/conducao';

@Injectable({ providedIn: 'root' })
export class ConducaoApi {
  private readonly http = inject(HttpClient);

  listar(filtros: FiltrosConducao, cursor: string) {
    return this.http.get<PaginaConducao>('/api/conducao/eventos', { params: { ...filtros, cursor } });
  }
}
