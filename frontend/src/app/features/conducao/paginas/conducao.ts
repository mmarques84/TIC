import { Component, ElementRef, inject, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { LinhaRanking, TIPOS_CONDUCAO, VisaoConducao, acimaDoDobro, fmt, textoVezes } from '../dominio/conducao';
import { ConducaoStore } from '../estado/conducao-store';
import { RankingStore } from '../estado/ranking-store';

// Tela Condução (spec relatorio-conducao; layout aprovado em 28/11/2026, artboard 10).
// Em cima: ranking por motorista ou caminhão (segunda entrega). Embaixo: a consulta de eventos (primeira entrega).
@Component({
  selector: 'tic-conducao',
  imports: [FormsModule, RouterLink],
  providers: [ConducaoStore, RankingStore],
  templateUrl: './conducao.html',
  styleUrl: './conducao.css',
})
export class Conducao {
  readonly store = inject(ConducaoStore);
  readonly ranking = inject(RankingStore);
  readonly tipos = TIPOS_CONDUCAO;
  readonly opcoes = Object.entries(this.tipos);
  readonly periodos = [
    { valor: 'hoje', nome: 'Hoje' }, { valor: '7', nome: '7 dias' },
    { valor: 'mes', nome: 'Mês atual' }, { valor: 'anterior', nome: 'Mês anterior' },
  ];
  readonly fmt = fmt;
  readonly textoVezes = textoVezes;
  readonly acimaDoDobro = acimaDoDobro;
  private readonly listaEventos = viewChild<ElementRef<HTMLElement>>('listaEventos');

  private readonly parametros = inject(ActivatedRoute).snapshot.queryParamMap;
  readonly filtros = {
    periodo: this.parametros.get('periodo') || '7',
    placa: this.parametros.get('placa') || '',
    tipo: this.parametros.get('tipo') || '',
  };
  motorista = this.parametros.get('motorista') || '';
  readonly operacao = this.parametros.get('operacao') || '';
  private readonly formato = new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo',
  });
  private readonly hora = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

  ngOnInit() {
    void this.ranking.mudar({ periodo: this.filtros.periodo, tipo: this.filtros.tipo });
    this.filtrar();
  }

  filtrar() {
    void this.store.filtrar({
      ...this.filtros, placa: this.filtros.placa.trim(), motorista: this.motorista, operacao: this.operacao,
    });
  }

  periodo(valor: string) {
    this.filtros.periodo = valor;
    void this.ranking.mudar({ periodo: valor });
    this.filtrar();
  }

  visao(v: VisaoConducao) { void this.ranking.mudar({ visao: v }); }
  tipo(valor: string) { this.filtros.tipo = valor; void this.ranking.mudar({ tipo: valor }); this.filtrar(); }
  buscar(valor: string) { void this.ranking.mudar({ q: valor.trim() }); }

  /** "Ver todos os eventos": filtra a lista de baixo pelo motorista (ou placa) da linha e rola até ela. */
  verEventos(l: LinhaRanking) {
    if (this.ranking.filtros().visao === 'motorista') {
      this.motorista = l.chave === 'sem_motorista' ? '' : l.chave;
      this.filtros.placa = '';
    } else {
      this.motorista = '';
      this.filtros.placa = l.nome;
    }
    this.filtrar();
    this.listaEventos()?.nativeElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  limparMotorista() { this.motorista = ''; this.filtrar(); }

  formatar(horario: string) { return this.formato.format(new Date(horario)); }
  horaDe(horario: string | null) { return horario ? this.hora.format(new Date(horario)) : '—'; }
  altura(eventos: number, dias: { eventos: number }[]) {
    const max = Math.max(1, ...dias.map((d) => d.eventos));
    return Math.max(4, Math.round((eventos / max) * 80)) + 'px';
  }
}
