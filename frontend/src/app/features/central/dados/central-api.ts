import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { AlertaDetalhe, AlertaFila, ResumoCentral } from '../dominio/central';

export interface FiltroCentral {
  aba: 'abertos' | 'tratados';
  nivel: string;
  tipo: string;
  q: string;
}

// Porta da Central (n8n api-central → derivado.sp_central_* / sp_alerta_*).
@Injectable({ providedIn: 'root' })
export class CentralApi {
  private readonly http = inject(HttpClient);

  listar(f: FiltroCentral): Observable<AlertaFila[]> {
    return this.http.get<AlertaFila[]>('/api/central/alertas', { params: { aba: f.aba, nivel: f.nivel, tipo: f.tipo, q: f.q } });
  }
  resumo(): Observable<ResumoCentral> {
    return this.http.get<ResumoCentral>('/api/central/resumo');
  }
  detalhe(id: string): Observable<AlertaDetalhe> {
    return this.http.get<AlertaDetalhe>('/api/central/alerta', { params: { id } });
  }
  assumir(id: string): Observable<AlertaFila> {
    return this.http.post<AlertaFila>('/api/central/alerta/assumir', { id });
  }
  confirmar(id: string, observacao: string): Observable<AlertaFila> {
    return this.http.post<AlertaFila>('/api/central/alerta/confirmar', { id, observacao });
  }
  falso(id: string, motivo: string, observacao: string): Observable<AlertaFila> {
    return this.http.post<AlertaFila>('/api/central/alerta/falso', { id, motivo, observacao });
  }
  mensagem(id: string, texto: string): Observable<AlertaFila> {
    return this.http.post<AlertaFila>('/api/central/alerta/mensagem', { id, texto });
  }
  sirene(id: string): Observable<AlertaFila> {
    return this.http.post<AlertaFila>('/api/central/alerta/sirene', { id });
  }
}
