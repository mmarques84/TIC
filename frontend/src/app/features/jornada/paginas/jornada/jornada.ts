import { Component, OnInit, computed, inject, signal } from '@angular/core';

import { Sessao } from '../../../../core/auth/sessao';
import { JornadaStore } from '../../estado/jornada.store';
import {
  COR_STATUS, DetalheMotorista, FAIXAS, FiltroDias, NOME_MACRO, NOME_SITUACAO, NOME_STATUS, NOME_TRATATIVA, ResumoJornada, TIPOS_TRATATIVA,
  dataHora, desde, diaSemana, hm, hora, larguraBarra, nivelDias,
} from '../../dominio/jornada';

@Component({
  selector: 'tic-jornada',
  providers: [JornadaStore],
  templateUrl: './jornada.html',
  styleUrl: './jornada.scss',
})
export class Jornada implements OnInit {
  readonly store = inject(JornadaStore);
  private readonly sessao = inject(Sessao);

  readonly faixas = FAIXAS;
  readonly dias: { valor: FiltroDias; nome: string }[] = [
    { valor: '', nome: 'Todos' }, { valor: '0-2', nome: '0–2' }, { valor: '3-5', nome: '3–5' }, { valor: '6', nome: '6' }, { valor: '7+', nome: '7+' },
  ];
  readonly tipos = TIPOS_TRATATIVA;
  readonly nomeStatus = NOME_STATUS;
  readonly corStatus = COR_STATUS;
  readonly nomeTratativa = NOME_TRATATIVA;
  readonly nomeSituacao = NOME_SITUACAO;
  readonly nomeMacro = NOME_MACRO;
  readonly hm = hm;
  readonly larguraBarra = larguraBarra;
  readonly nivelDias = nivelDias;
  readonly dataHora = dataHora;
  readonly hora = hora;
  readonly diaSemana = diaSemana;

  readonly podeTratar = computed(() => this.sessao.pode('jornada.tratar'));
  readonly tTipo = signal('');
  readonly tObs = signal('');
  readonly tJornada = signal('');

  ngOnInit(): void {
    this.store.iniciar();
  }

  contagem(r: ResumoJornada | null, chave: string): number {
    if (!r) return 0;
    return (chave ? (r as unknown as Record<string, number>)[chave] : r.todos) ?? 0;
  }

  desde(iso: string | null): string {
    return desde(iso, this.store.agora());
  }

  /** Jornadas que pedem tratativa própria (sem fim ou inconsistente). */
  jornadasParaTratar(d: DetalheMotorista) {
    return d.jornadas.filter((j) => j.situacao === 'sem_fim' || j.situacao === 'inconsistente');
  }

  v(ev: Event): string {
    return (ev.target as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement).value;
  }

  async abrir(id: string): Promise<void> {
    this.tTipo.set('');
    this.tObs.set('');
    this.tJornada.set('');
    await this.store.alternar(id);
  }

  async salvar(ev: Event): Promise<void> {
    ev.preventDefault();
    const ok = await this.store.tratar(this.tTipo(), this.tObs(), this.tJornada() || null);
    if (ok) {
      this.tTipo.set('');
      this.tObs.set('');
      this.tJornada.set('');
    }
  }
}
