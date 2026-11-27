import { Component, OnInit, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { primeiroNome } from '../../../../core/auth/dominio/usuario';
import { Sessao } from '../../../../core/auth/sessao';
import { DADOS_FICTICIOS } from '../../../../core/config';
import { saudacao } from '../../dominio/inicio';
import { InicioStore } from '../../estado/inicio.store';

@Component({
  selector: 'tic-inicio',
  imports: [RouterLink],
  providers: [InicioStore],
  templateUrl: './inicio.html',
  styleUrl: './inicio.scss',
})
export class Inicio implements OnInit {
  private readonly sessao = inject(Sessao);
  readonly store = inject(InicioStore);
  // Enquanto /api/inicio não existir, os números são de exemplo: a tela avisa (nunca parecer dado real).
  readonly ficticio = DADOS_FICTICIOS.inicio;

  readonly titulo = computed(() => `${saudacao(new Date())}, ${primeiroNome(this.sessao.usuario())}`);
  readonly podeAlertas = computed(() => this.sessao.pode('alerta.ver'));
  readonly atualizado = computed(() => {
    const r = this.store.resumo();
    return r ? new Date(r.geradoEm).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '';
  });

  ngOnInit(): void {
    this.store.iniciar();
  }
}
