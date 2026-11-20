import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, delay, of, throwError } from 'rxjs';

import { ErroRegra } from '../../api/erro-api';
import { Perfil, Permissao, Usuario } from '../dominio/usuario';

// Porta (clean): o resto do app só conhece esta classe abstrata.
// Duas implementações: HTTP (n8n → sp_*) e fictícia (até o backend existir). Escolha em app.config.ts.
export abstract class AuthApi {
  abstract me(): Observable<Usuario>;
  abstract login(email: string, senha: string): Observable<Usuario>;
  abstract logout(): Observable<void>;
  abstract esqueci(email: string): Observable<void>;
  abstract definirSenha(token: string, senha: string): Observable<Usuario>;
  abstract consultarLink(token: string): Observable<{ email: string; perfil: Perfil; expiraEm: string }>;
}

@Injectable()
export class AuthApiHttp extends AuthApi {
  private readonly http = inject(HttpClient);
  me() {
    return this.http.get<Usuario>('/api/auth/me');
  }
  login(email: string, senha: string) {
    return this.http.post<Usuario>('/api/auth/login', { email, senha });
  }
  logout() {
    return this.http.post<void>('/api/auth/logout', {});
  }
  esqueci(email: string) {
    return this.http.post<void>('/api/auth/senha/esqueci', { email });
  }
  definirSenha(token: string, senha: string) {
    return this.http.post<Usuario>('/api/auth/senha/definir', { token, senha });
  }
  consultarLink(token: string) {
    return this.http.get<{ email: string; perfil: Perfil; expiraEm: string }>('/api/auth/senha/link', { params: { token } });
  }
}

// ===== Dados fictícios (desenvolvimento). Nenhum dado real. =====

export const SENHA_FICTICIA = 'tic-demo-2026';

const PERMISSOES: Record<Perfil, Permissao[]> = {
  diretoria: ['alerta.ver', 'imagem.ver', 'jornada.ver', 'torre.ver', 'opi.ver', 'cockpit.ver', 'consumo_ia.ver'],
  operacao: ['alerta.ver', 'alerta.tratar', 'alerta.acionar', 'imagem.ver', 'jornada.ver', 'jornada.tratar', 'torre.ver', 'cockpit.ver', 'parametro.ver'],
  frota_opi: ['alerta.ver', 'alerta.tratar', 'imagem.ver', 'jornada.ver', 'jornada.tratar', 'opi.ver', 'opi.validar', 'triagem.validar', 'cockpit.ver', 'parametro.ver'],
  central: ['alerta.ver', 'alerta.tratar', 'alerta.acionar', 'imagem.ver', 'torre.ver'],
  ti: ['consumo_ia.ver', 'integracao.ver', 'auditoria.ver'],
  admin: [
    'alerta.ver', 'alerta.tratar', 'alerta.acionar', 'imagem.ver', 'jornada.ver', 'jornada.tratar', 'torre.ver', 'opi.ver', 'opi.validar',
    'triagem.validar', 'cockpit.ver', 'consumo_ia.ver', 'parametro.ver', 'parametro.editar', 'usuario.gerir', 'integracao.ver', 'auditoria.ver',
  ],
};

const NOMES: Record<Perfil, string> = {
  diretoria: 'Diretoria Exemplo',
  operacao: 'Operação Exemplo',
  frota_opi: 'Frota Exemplo',
  central: 'Central Exemplo',
  ti: 'TI Exemplo',
  admin: 'Admin Exemplo',
};

export function usuarioFicticio(perfil: Perfil): Usuario {
  return {
    id: `ficticio-${perfil}`,
    nome: NOMES[perfil],
    email: `${perfil.replace('_', '')}@exemplo.com`,
    perfil,
    permissoes: PERMISSOES[perfil],
    operacoes: [],
    todasOperacoes: true,
  };
}

const CHAVE = 'tic.sessao.ficticia';

@Injectable()
export class AuthApiFicticia extends AuthApi {
  me() {
    const perfil = ler();
    return perfil ? of(usuarioFicticio(perfil)).pipe(delay(150)) : throwError(() => new ErroRegra('SEM_SESSAO', 401));
  }
  login(email: string, senha: string) {
    const perfil = (Object.keys(NOMES) as Perfil[]).find((p) => usuarioFicticio(p).email === email);
    if (!perfil || senha !== SENHA_FICTICIA) return throwError(() => new ErroRegra('CREDENCIAIS_INVALIDAS', 401)).pipe(delay(400));
    gravar(perfil);
    return of(usuarioFicticio(perfil)).pipe(delay(400));
  }
  logout() {
    gravar(null);
    return of(undefined).pipe(delay(100));
  }
  esqueci() {
    return of(undefined).pipe(delay(500)); // sempre responde igual: não revela se o e-mail existe
  }
  consultarLink(token: string) {
    if (!token) return throwError(() => new ErroRegra('LINK_INVALIDO', 400));
    return of({ email: 'frotaopi@exemplo.com', perfil: 'frota_opi' as Perfil, expiraEm: new Date(Date.now() + 864e5).toISOString() }).pipe(delay(200));
  }
  definirSenha() {
    gravar('frota_opi');
    return of(usuarioFicticio('frota_opi')).pipe(delay(400));
  }
}

function ler(): Perfil | null {
  try {
    return (sessionStorage.getItem(CHAVE) as Perfil | null) ?? null;
  } catch {
    return null;
  }
}

function gravar(perfil: Perfil | null): void {
  try {
    if (perfil) sessionStorage.setItem(CHAVE, perfil);
    else sessionStorage.removeItem(CHAVE);
  } catch {
    /* navegação privada: sessão só em memória */
  }
}
