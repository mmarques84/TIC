import { DestroyRef, Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { paraErroApi } from '../../../core/api/erro-api';
import { Sessao } from '../../../core/auth/sessao';
import { InicioApi } from '../dados/inicio-api';
import { LinhaSimples, ResumoInicio, TITULO_PAINEL, composicaoDoPerfil, indicadoresDoPerfil } from '../dominio/inicio';

const INTERVALO_MS = 30000; // spec inicio-resumo R15: a cada 30 s (o resumo junta várias tabelas)

// Estado da tela Início. O componente só lê signals daqui; nunca chama HTTP.
@Injectable()
export class InicioStore {
  private readonly api = inject(InicioApi);
  private readonly sessao = inject(Sessao);
  private timer: ReturnType<typeof setInterval> | null = null;

  private readonly _resumo = signal<ResumoInicio | null>(null);
  private readonly _erro = signal('');
  readonly carregando = computed(() => !this._resumo() && !this._erro());
  readonly erro = this._erro.asReadonly();
  readonly resumo = this._resumo.asReadonly();

  readonly composicao = computed(() => {
    const u = this.sessao.usuario();
    return u ? composicaoDoPerfil(u.perfil) : null;
  });

  readonly indicadores = computed(() => {
    const u = this.sessao.usuario();
    const r = this._resumo();
    return u && r ? indicadoresDoPerfil(u.perfil, r.indicadores) : [];
  });

  readonly lateral = computed(() => {
    const c = this.composicao();
    const r = this._resumo();
    if (!c || !r) return null;
    const linhas: LinhaSimples[] = c.lateral === 'integracoes'
      ? r.integracoes.map((i) => ({ id: i.fonte, titulo: i.fonte, detalhe: i.texto, selo: { ok: 'OK', atraso: 'Atraso', erro: 'Erro', inativa: 'Inativa' }[i.estado], nivel: i.estado === 'ok' ? 'ok' : i.estado === 'inativa' ? 'neutro' : 'medio' }))
      : r[c.lateral];
    return { ...TITULO_PAINEL[c.lateral], linhas };
  });

  constructor() {
    inject(DestroyRef).onDestroy(() => this.parar());
  }

  iniciar(): void {
    void this.carregar();
    this.timer ??= setInterval(() => void this.carregar(), INTERVALO_MS);
  }

  parar(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  private async carregar(): Promise<void> {
    try {
      this._resumo.set(await firstValueFrom(this.api.resumo()));
      this._erro.set('');
    } catch (e) {
      const err = paraErroApi(e);
      if (!this._resumo()) this._erro.set(err.semConexao ? 'Sem conexão com o servidor.' : 'Não foi possível carregar o resumo.');
    }
  }
}
