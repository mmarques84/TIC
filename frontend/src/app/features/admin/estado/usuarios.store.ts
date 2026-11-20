import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../core/api/erro-api';
import { AdminApi, MudancaUsuario, NovoUsuario } from '../dados/admin-api';
import { LinkGerado, PerfilOpcao, SessaoAberta, UsuarioAdmin, contagem, filtrar, mensagemAdmin } from '../dominio/usuarios';

export type Modal = '' | 'novo' | 'link' | 'desativar';

// Estado da tela Usuários e perfis. A página só lê signals e chama ações daqui.
@Injectable()
export class UsuariosStore {
  private readonly api = inject(AdminApi);

  readonly lista = signal<UsuarioAdmin[]>([]);
  readonly perfis = signal<PerfilOpcao[]>([]);
  readonly carregando = signal(true);
  readonly erroLista = signal('');
  readonly busca = signal('');
  readonly filtroPerfil = signal('');
  readonly selecionadoId = signal<string | null>(null);
  readonly aba = signal<'dados' | 'acessos'>('dados');
  readonly sessoes = signal<SessaoAberta[]>([]);
  readonly modal = signal<Modal>('');
  readonly link = signal<LinkGerado | null>(null);
  readonly ocupado = signal(false);
  readonly erro = signal('');
  readonly aviso = signal('');

  readonly visiveis = computed(() => filtrar(this.lista(), this.busca(), this.filtroPerfil()));
  readonly resumo = computed(() => contagem(this.lista()));
  readonly selecionado = computed(() => this.lista().find((u) => u.id === this.selecionadoId()) ?? null);

  async carregar(): Promise<void> {
    this.carregando.set(true);
    try {
      const [lista, perfis] = await Promise.all([firstValueFrom(this.api.listar()), firstValueFrom(this.api.perfis())]);
      this.lista.set(lista);
      this.perfis.set(perfis);
      this.erroLista.set('');
    } catch (e) {
      this.erroLista.set(mensagemAdmin(paraErroApi(e).codigo));
    } finally {
      this.carregando.set(false);
    }
  }

  abrir(id: string): void {
    this.selecionadoId.set(id);
    this.aba.set('dados');
    this.erro.set('');
    this.aviso.set('');
  }

  fechar(): void {
    this.selecionadoId.set(null);
  }

  async verAcessos(): Promise<void> {
    this.aba.set('acessos');
    const id = this.selecionadoId();
    if (id) await this.executar(async () => this.sessoes.set(await firstValueFrom(this.api.sessoes(id))));
  }

  async criar(dados: NovoUsuario): Promise<void> {
    await this.executar(async () => {
      const novo = await firstValueFrom(this.api.criar(dados));
      this.lista.update((l) => [...l, novo].sort(ordem));
      this.selecionadoId.set(novo.id);
      this.link.set(await firstValueFrom(this.api.gerarLink(novo.id)));
      this.modal.set('link');
    });
  }

  async salvar(mudanca: MudancaUsuario): Promise<void> {
    const id = this.selecionadoId();
    if (!id) return;
    await this.executar(async () => {
      const r = await firstValueFrom(this.api.atualizar(id, mudanca));
      this.substituir(r);
      this.aviso.set(r.sessoesEncerradas > 0 ? `Salvo. ${r.sessoesEncerradas} acesso(s) aberto(s) encerrado(s).` : 'Salvo.');
      this.modal.set('');
    });
  }

  async gerarLink(): Promise<void> {
    const id = this.selecionadoId();
    if (!id) return;
    await this.executar(async () => {
      this.link.set(await firstValueFrom(this.api.gerarLink(id)));
      this.modal.set('link');
    });
  }

  async encerrarSessao(sessaoId: string): Promise<void> {
    await this.executar(async () => {
      await firstValueFrom(this.api.encerrarSessao(sessaoId));
      this.sessoes.update((s) => s.filter((x) => x.id !== sessaoId));
    });
  }

  async encerrarTodas(): Promise<void> {
    const id = this.selecionadoId();
    if (!id) return;
    await this.executar(async () => {
      const r = await firstValueFrom(this.api.encerrarTodas(id));
      this.sessoes.set([]);
      this.aviso.set(`${r.encerradas} acesso(s) encerrado(s).`);
    });
  }

  fecharModal(): void {
    this.modal.set('');
    this.link.set(null); // R12: o link não volta depois de fechado
    this.erro.set('');
  }

  private substituir(u: UsuarioAdmin): void {
    this.lista.update((l) => l.map((x) => (x.id === u.id ? u : x)).sort(ordem));
  }

  private async executar(acao: () => Promise<void>): Promise<void> {
    if (this.ocupado()) return;
    this.ocupado.set(true);
    this.erro.set('');
    try {
      await acao();
    } catch (e) {
      this.erro.set(mensagemAdmin(paraErroApi(e).codigo));
    } finally {
      this.ocupado.set(false);
    }
  }
}

function ordem(a: UsuarioAdmin, b: UsuarioAdmin): number {
  return Number(b.ativo) - Number(a.ativo) || a.nome.localeCompare(b.nome, 'pt-BR');
}
