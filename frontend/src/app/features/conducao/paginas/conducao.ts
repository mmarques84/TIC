import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { TIPOS_CONDUCAO } from '../dominio/conducao';
import { ConducaoStore } from '../estado/conducao-store';

@Component({
  selector: 'tic-conducao',
  imports: [FormsModule, RouterLink],
  providers: [ConducaoStore],
  templateUrl: './conducao.html',
  styleUrl: './conducao.css',
})
export class Conducao {
  readonly store = inject(ConducaoStore);
  readonly tipos = TIPOS_CONDUCAO;
  readonly opcoes = Object.entries(this.tipos);
  private readonly parametros = inject(ActivatedRoute).snapshot.queryParamMap;
  readonly filtros = {
    periodo: this.parametros.get('periodo') || '7',
    placa: this.parametros.get('placa') || '',
    tipo: this.parametros.get('tipo') || '',
  };
  readonly motorista = this.parametros.get('motorista') || '';
  readonly operacao = this.parametros.get('operacao') || '';
  private readonly formato = new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo',
  });

  ngOnInit() { this.filtrar(); }

  filtrar() {
    void this.store.filtrar({
      ...this.filtros, placa: this.filtros.placa.trim(), motorista: this.motorista, operacao: this.operacao,
    });
  }

  formatar(horario: string) { return this.formato.format(new Date(horario)); }
}
