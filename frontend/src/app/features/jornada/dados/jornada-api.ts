import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { DetalheMotorista, Faixa, FiltroDias, MotoristaJornada, ResumoJornada } from '../dominio/jornada';

export interface FiltroJornada {
  faixa: Faixa;
  dias: FiltroDias;
  q: string;
  semControle: boolean;
}

// Porta da tela de Jornada (n8n api-jornada → derivado.sp_jornada_* / sp_tratativa_criar).
@Injectable({ providedIn: 'root' })
export class JornadaApi {
  private readonly http = inject(HttpClient);

  listar(f: FiltroJornada): Observable<MotoristaJornada[]> {
    return this.http.get<MotoristaJornada[]>('/api/jornada/motoristas', {
      params: { faixa: f.faixa, dias: f.dias, q: f.q, semcontrole: String(f.semControle) },
    });
  }
  resumo(): Observable<ResumoJornada> {
    return this.http.get<ResumoJornada>('/api/jornada/resumo');
  }
  detalhe(id: string): Observable<DetalheMotorista> {
    return this.http.get<DetalheMotorista>('/api/jornada/motorista', { params: { id } });
  }
  tratativa(motorista: string, jornada: string | null, tipo: string, observacao: string): Observable<MotoristaJornada> {
    return this.http.post<MotoristaJornada>('/api/jornada/tratativa', { motorista, jornada: jornada ?? '', tipo, observacao });
  }
}
