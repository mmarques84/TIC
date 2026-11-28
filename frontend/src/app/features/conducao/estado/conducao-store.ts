import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ConducaoApi } from '../dados/conducao-api';
import { FiltrosConducao, PaginaConducao } from '../dominio/conducao';

@Injectable()
export class ConducaoStore {
  private readonly api = inject(ConducaoApi);
  private filtros: FiltrosConducao = { periodo: '7', placa: '', tipo: '' };
  private cursores = [''];
  readonly pagina = signal(0);
  readonly dados = signal<PaginaConducao | null>(null);
  readonly carregando = signal(false);
  readonly erro = signal('');

  filtrar(filtros: FiltrosConducao) {
    this.filtros = filtros;
    this.cursores = [''];
    this.pagina.set(0);
    return this.carregar();
  }

  avancar() {
    const cursor = this.dados()?.proximo;
    if (!cursor || this.carregando()) return;
    this.cursores[this.pagina() + 1] = cursor;
    this.pagina.update(pagina => pagina + 1);
    return this.carregar();
  }

  voltar() {
    if (!this.pagina() || this.carregando()) return;
    this.pagina.update(pagina => pagina - 1);
    return this.carregar();
  }

  async carregar() {
    this.carregando.set(true);
    this.erro.set('');
    this.dados.set(null);
    try {
      this.dados.set(await firstValueFrom(this.api.listar(this.filtros, this.cursores[this.pagina()])));
    } catch {
      this.erro.set('Não foi possível carregar os eventos.');
    } finally {
      this.carregando.set(false);
    }
  }
}
