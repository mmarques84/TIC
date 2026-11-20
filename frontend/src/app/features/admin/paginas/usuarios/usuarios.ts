import { Component, OnInit, computed, effect, inject, signal } from '@angular/core';

import { Sessao } from '../../../../core/auth/sessao';
import { UsuariosStore } from '../../estado/usuarios.store';
import { aparelho, dataHora, operacoesTexto } from '../../dominio/usuarios';

@Component({
  selector: 'tic-admin-usuarios',
  providers: [UsuariosStore],
  templateUrl: './usuarios.html',
  styleUrl: './usuarios.scss',
})
export class AdminUsuarios implements OnInit {
  readonly store = inject(UsuariosStore);
  private readonly sessao = inject(Sessao);

  readonly opTexto = operacoesTexto;
  readonly quando = dataHora;
  readonly aparelho = aparelho;
  readonly euId = computed(() => this.sessao.usuario()?.id ?? '');

  // Formulário "Novo usuário"
  readonly nNome = signal('');
  readonly nEmail = signal('');
  readonly nPerfil = signal('');

  // Formulário da ficha (cópia editável do selecionado)
  readonly fNome = signal('');
  readonly fEmail = signal('');
  readonly fPerfil = signal('');
  readonly mudouPerfil = computed(() => !!this.store.selecionado() && this.fPerfil() !== this.store.selecionado()!.perfil);
  readonly copiado = signal(false);

  constructor() {
    effect(() => {
      const u = this.store.selecionado();
      this.fNome.set(u?.nome ?? '');
      this.fEmail.set(u?.email ?? '');
      this.fPerfil.set(u?.perfil ?? '');
    });
  }

  ngOnInit(): void {
    void this.store.carregar();
  }

  v(ev: Event): string {
    return (ev.target as HTMLInputElement | HTMLSelectElement).value;
  }

  abrirNovo(): void {
    this.nNome.set('');
    this.nEmail.set('');
    this.nPerfil.set('');
    this.store.erro.set('');
    this.store.modal.set('novo');
  }

  async criar(ev: Event): Promise<void> {
    ev.preventDefault();
    if (!this.nNome().trim() || !this.nEmail().trim() || !this.nPerfil()) {
      this.store.erro.set('Preencha nome, e-mail e perfil.');
      return;
    }
    await this.store.criar({ nome: this.nNome(), email: this.nEmail(), perfil: this.nPerfil(), todasOperacoes: true, operacoes: [] });
  }

  async salvarFicha(ev: Event): Promise<void> {
    ev.preventDefault();
    const u = this.store.selecionado();
    if (!u) return;
    const m: { nome?: string; email?: string; perfil?: string } = {};
    if (this.fNome().trim() !== u.nome) m.nome = this.fNome();
    if (this.fEmail().trim().toLowerCase() !== u.email) m.email = this.fEmail();
    if (this.fPerfil() !== u.perfil) m.perfil = this.fPerfil();
    if (!Object.keys(m).length) {
      this.store.aviso.set('Nada mudou.');
      return;
    }
    await this.store.salvar(m);
  }

  async copiar(link: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(link);
      this.copiado.set(true);
      setTimeout(() => this.copiado.set(false), 2500);
    } catch {
      this.copiado.set(false);
    }
  }
}
