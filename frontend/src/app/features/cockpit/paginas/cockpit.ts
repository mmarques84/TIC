import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { TIPOS_CONDUCAO } from '../../conducao/dominio/conducao';
import { CockpitStore } from '../estado/cockpit-store';

@Component({
  selector: 'tic-cockpit',
  imports: [FormsModule, RouterLink],
  providers: [CockpitStore],
  templateUrl: './cockpit.html',
  styleUrl: './cockpit.css',
})
export class Cockpit {
  readonly store = inject(CockpitStore);
  readonly tipos = TIPOS_CONDUCAO;
  readonly opcoes = Object.entries(this.tipos);
  readonly filtros = { periodo: '7', operacao: '', placa: '', tipo: '' };
  readonly visao = signal<'motoristas' | 'veiculos'>('motoristas');
  readonly completo = signal(false);
  readonly busca = signal('');
  readonly motoristasVisiveis = computed(() => {
    const resumo = this.store.resumo();
    if (!resumo) return [];
    const busca = this.normalizar(this.busca());
    const linhas = resumo.motoristas.filter(motorista =>
      this.normalizar(motorista.nome).includes(busca) || motorista.placas.some(placa => this.normalizar(placa).includes(busca)));
    return this.completo() || busca ? linhas : linhas.slice(0, resumo.limiteDestaques);
  });
  readonly veiculosVisiveis = computed(() => {
    const resumo = this.store.resumo();
    if (!resumo) return [];
    const busca = this.normalizar(this.busca());
    const linhas = resumo.veiculos.filter(veiculo => this.normalizar(veiculo.placa).includes(busca));
    return this.completo() || busca ? linhas : linhas.slice(0, resumo.limiteDestaques);
  });
  readonly indicadores = [
    { titulo: 'Eventos graves', fonte: 'Aguardando classificação de alertas' },
    { titulo: 'Tempo médio de resposta', fonte: 'Aguardando histórico de atendimento' },
    { titulo: 'Falsos positivos evitados', fonte: 'Aguardando triagem da IA' },
    { titulo: 'Motoristas reincidentes', fonte: 'Aguardando regra de reincidência' },
    { titulo: 'Conformidade OPI média', fonte: 'Aguardando avaliações OPI' },
  ];
  readonly semanas = computed(() => {
    const totais = new Map<string, number>();
    for (const { dia, total } of this.store.resumo()?.dias ?? []) {
      const segunda = new Date(dia);
      segunda.setUTCDate(segunda.getUTCDate() - (segunda.getUTCDay() + 6) % 7);
      const inicio = segunda.toISOString().slice(0, 10);
      totais.set(inicio, (totais.get(inicio) ?? 0) + total);
    }
    return [...totais].map(([inicio, total]) => ({ inicio, total }));
  });
  readonly maxSemana = computed(() => Math.max(1, ...this.semanas().map(semana => semana.total)));
  private readonly numero = new Intl.NumberFormat('pt-BR');
  private readonly horario = new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo',
  });
  private readonly dia = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit', month: '2-digit', timeZone: 'UTC',
  });

  ngOnInit() { void this.store.consultar(); }

  filtrar() {
    void this.store.consultar({ ...this.filtros, placa: this.filtros.placa.trim() });
  }

  limpar() {
    Object.assign(this.filtros, { periodo: '7', operacao: '', placa: '', tipo: '' });
    this.filtrar();
  }

  trocarVisao(visao: 'motoristas' | 'veiculos') {
    this.visao.set(visao);
    this.busca.set('');
    this.completo.set(false);
  }

  private normalizar(texto: string) {
    return texto.trim().normalize('NFD').replace(/[\u0300-\u036f-]/g, '').toLowerCase();
  }

  formatarDia(dia: string) { return this.dia.format(new Date(dia)); }
  formatarHorario(horario: string) { return this.horario.format(new Date(horario)); }
  formatarTotal(total: number) { return this.numero.format(total); }
}
