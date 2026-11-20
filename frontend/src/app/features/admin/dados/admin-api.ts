import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { LinkGerado, PerfilOpcao, SessaoAberta, UsuarioAdmin } from '../dominio/usuarios';

export interface NovoUsuario {
  nome: string;
  email: string;
  perfil: string;
  todasOperacoes: boolean;
  operacoes: string[];
}

export type MudancaUsuario = Partial<NovoUsuario & { ativo: boolean }>;

// Porta do Admin · Usuários (n8n api-admin → acesso.sp_usuario_* / sp_sessao_*). Id em ?id= ou no corpo.
@Injectable({ providedIn: 'root' })
export class AdminApi {
  private readonly http = inject(HttpClient);

  listar(): Observable<UsuarioAdmin[]> {
    return this.http.get<UsuarioAdmin[]>('/api/admin/usuarios');
  }
  perfis(): Observable<PerfilOpcao[]> {
    return this.http.get<PerfilOpcao[]>('/api/admin/perfis');
  }
  criar(dados: NovoUsuario): Observable<UsuarioAdmin> {
    return this.http.post<UsuarioAdmin>('/api/admin/usuarios', dados);
  }
  atualizar(id: string, mudanca: MudancaUsuario): Observable<UsuarioAdmin & { sessoesEncerradas: number }> {
    return this.http.patch<UsuarioAdmin & { sessoesEncerradas: number }>('/api/admin/usuarios', mudanca, { params: { id } });
  }
  gerarLink(id: string): Observable<LinkGerado> {
    return this.http.post<LinkGerado>('/api/admin/usuarios/link-senha', { id });
  }
  sessoes(usuario: string): Observable<SessaoAberta[]> {
    return this.http.get<SessaoAberta[]>('/api/admin/sessoes', { params: { usuario } });
  }
  encerrarSessao(id: string): Observable<{ ok: boolean }> {
    return this.http.delete<{ ok: boolean }>('/api/admin/sessoes', { params: { id } });
  }
  encerrarTodas(id: string): Observable<{ encerradas: number }> {
    return this.http.post<{ encerradas: number }>('/api/admin/usuarios/encerrar-sessoes', { id });
  }
}
