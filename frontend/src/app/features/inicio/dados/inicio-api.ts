import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, delay, of } from 'rxjs';

import { ResumoInicio } from '../dominio/inicio';

// Porta da tela Início. HTTP: GET /api/inicio (n8n → sp_inicio_resumo, já filtrado por perfil e operação).
export abstract class InicioApi {
  abstract resumo(): Observable<ResumoInicio>;
}

@Injectable()
export class InicioApiHttp extends InicioApi {
  private readonly http = inject(HttpClient);
  resumo() {
    return this.http.get<ResumoInicio>('/api/inicio');
  }
}

// Dados fictícios: placas TST*, motoristas "Motorista A…". Nenhum dado real.
@Injectable()
export class InicioApiFicticia extends InicioApi {
  resumo(): Observable<ResumoInicio> {
    return of<ResumoInicio>({
      geradoEm: new Date().toISOString(),
      indicadores: [
        { codigo: 'alertas', rotulo: 'Alertas abertos', valor: '12', nota: '3 críticos', nivelNota: 'critico' },
        { codigo: 'fadiga', rotulo: 'Fadiga na última hora', valor: '4', nota: '1 sirene acionada', nivelNota: 'critico' },
        { codigo: 'em_jornada', rotulo: 'Motoristas em jornada', valor: '118', nota: 'de 240 cadastrados', nivelNota: null },
        { codigo: 'violacoes', rotulo: 'Violações de jornada hoje', valor: '9', nota: '5 com tratativa', nivelNota: null },
        { codigo: 'falsos_evitados', rotulo: 'Falsos positivos evitados', valor: '71%', nota: 'dos alarmes de hoje', nivelNota: 'ok' },
        { codigo: 'opi_mes', rotulo: 'OPIs do mês', valor: '118/240', nota: '14 aguardando validação', nivelNota: 'medio' },
        { codigo: 'consumo_ia', rotulo: 'Consumo de IA no mês', valor: '64%', nota: 'do teto · projeção 78%', nivelNota: null },
        { codigo: 'integracoes', rotulo: 'Integrações', valor: '3/4', nota: 'Moovsec com atraso', nivelNota: 'medio' },
      ],
      alertas: [
        { id: 'a1', nivel: 'critico', rotuloNivel: 'Crítico', titulo: 'Fadiga: 11 bocejos na última hora', detalhe: 'Sirene acionada · IA: verdadeiro (alta)', placa: 'TST1A01', motorista: 'Motorista A', ha: 'há 3 min' },
        { id: 'a2', nivel: 'grave', rotuloNivel: 'Grave', titulo: 'Freada brusca + distração', detalhe: 'Imagem do mesmo instante · IA: verdadeiro (média)', placa: 'TST2B02', motorista: 'Motorista B', ha: 'há 9 min' },
        { id: 'a3', nivel: 'grave', rotuloNivel: 'Grave', titulo: 'Sem cinto há 14 s', detalhe: 'IA: inconclusivo · imagem escura', placa: 'TST3C03', motorista: 'Motorista C', ha: 'há 15 min' },
        { id: 'a4', nivel: 'medio', rotuloNivel: 'Médio', titulo: 'Velocidade 85 km/h, pista molhada', detalhe: 'Limpador ligado · limite 66 km/h', placa: 'TST4D04', motorista: 'Motorista D', ha: 'há 22 min' },
        { id: 'a5', nivel: 'leve', rotuloNivel: 'Leve', titulo: 'Fadiga: 5 bocejos na última hora', detalhe: 'Mensagem enviada ao terminal', placa: 'TST5E05', motorista: 'Motorista E', ha: 'há 31 min' },
      ],
      jornada: [
        { id: 'j1', titulo: 'Motorista F', detalhe: 'Sem descanso de 35 h · TST6F06', selo: '7 dias', nivel: 'grave' },
        { id: 'j2', titulo: 'Motorista G', detalhe: 'Jornada acima de 12 h · em direção', selo: '12h40', nivel: 'grave' },
        { id: 'j3', titulo: 'Motorista H', detalhe: 'Parado 36 h com jornada aberta', selo: 'Conferir', nivel: 'medio' },
        { id: 'j4', titulo: 'Motorista I', detalhe: 'Interjornada de 9h50 (mín. 11 h)', selo: '9h50', nivel: 'medio' },
        { id: 'j5', titulo: 'Motorista J', detalhe: 'Outro motorista logado no veículo', selo: 'Conferir', nivel: 'medio' },
      ],
      opi: [
        { id: 'o1', titulo: 'Motorista K', detalhe: 'IA: 86% · baixa confiança no item 6', selo: 'Validar', nivel: 'medio' },
        { id: 'o2', titulo: 'Motorista L', detalhe: 'IA: 92% · imagem noturna', selo: 'Validar', nivel: 'medio' },
        { id: 'o3', titulo: 'Motorista M', detalhe: '100% · validado por humano', selo: 'Validada', nivel: 'ok' },
        { id: 'o4', titulo: 'Motorista N', detalhe: 'Trecho 06:00–06:15 escolhido', selo: 'Gerando', nivel: 'neutro' },
        { id: 'o5', titulo: 'Motorista O', detalhe: '95% · orientação sugerida', selo: 'Validada', nivel: 'ok' },
      ],
      consumo: [
        { id: 'c1', titulo: 'Triagem de alarmes', detalhe: 'Modelo pequeno · 41 mil análises no mês', selo: '62%', nivel: 'neutro' },
        { id: 'c2', titulo: 'OPI de condução', detalhe: 'Modelo maior · 118 OPIs', selo: '31%', nivel: 'neutro' },
        { id: 'c3', titulo: 'Reanálise (baixa confiança)', detalhe: 'Só alarmes graves', selo: '7%', nivel: 'neutro' },
        { id: 'c4', titulo: 'Projeção do mês', detalhe: '78% do teto até o fim do mês', selo: 'No ritmo', nivel: 'ok' },
      ],
      integracoes: [
        { fonte: 'Autotrac', estado: 'ok', texto: 'há 40 s' },
        { fonte: 'Moovsec', estado: 'atraso', texto: 'atraso de 12 min' },
        { fonte: 'IA', estado: 'ok', texto: 'ok' },
        { fonte: 'Datapar', estado: 'inativa', texto: 'não contratado' },
      ],
    }).pipe(delay(250));
  }
}
