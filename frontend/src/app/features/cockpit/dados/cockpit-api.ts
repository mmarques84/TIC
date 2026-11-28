import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { FiltrosCockpit, ResumoCockpit } from '../dominio/cockpit';

@Injectable({ providedIn: 'root' })
export class CockpitApi {
  private readonly http = inject(HttpClient);

  consultar(filtros: FiltrosCockpit) {
    return this.http.get<ResumoCockpit>('/api/cockpit/resumo', { params: { ...filtros } });
  }
}
