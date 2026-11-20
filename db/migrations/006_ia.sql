-- 006 · IA: triagem de alarmes, OPI (modelo do formulário e respostas) e consumo.

CREATE TABLE ia.triagem (
  id              uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  evento_id       uuid NOT NULL REFERENCES derivado.evento (id) ON DELETE RESTRICT,
  rodada          smallint NOT NULL DEFAULT 1 CHECK (rodada BETWEEN 1 AND 3),   -- 2 = reanálise com modelo maior
  resultado       text NOT NULL CHECK (resultado IN ('verdadeiro', 'falso', 'inconclusivo')),
  confianca       text NOT NULL CHECK (confianca IN ('alta', 'media', 'baixa')),
  evidencia       text NOT NULL CHECK (length(evidencia) BETWEEN 3 AND 1000),
  modelo          text NOT NULL,
  prompt_versao   text NOT NULL,
  custo_usd       numeric(12,6) NOT NULL DEFAULT 0 CHECK (custo_usd >= 0),
  validado_por    uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  validacao       text NULL CHECK (validacao IN ('concordo', 'discordo')),
  validado_em     timestamptz NULL,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (evento_id, rodada),
  CHECK ((validado_por IS NULL) = (validacao IS NULL))
);

-- Formulário OPI (FFRO 005 rev5). Um modelo novo = novas linhas, o antigo continua para o histórico.
CREATE TABLE ia.opi_modelo (
  codigo          text PRIMARY KEY CHECK (codigo ~ '^[A-Z0-9_-]+$'),
  nome            text NOT NULL,
  revisao         text NOT NULL,
  vigente_desde   date NOT NULL,
  ativo           boolean NOT NULL DEFAULT true
);

CREATE TABLE ia.opi_modelo_item (
  modelo             text NOT NULL REFERENCES ia.opi_modelo (codigo) ON DELETE RESTRICT,
  numero             smallint NOT NULL CHECK (numero BETWEEN 1 AND 99),
  secao              text NOT NULL CHECK (secao IN ('antes_viagem', 'procedimentos_empresa', 'direcao_segura', 'apos_viagem', 'cameras')),
  texto              text NOT NULL,
  invertido          boolean NOT NULL DEFAULT false,   -- a pergunta descreve o problema: SIM = não atendido
  so_nao_anunciada   boolean NOT NULL DEFAULT false,
  avaliado_por       text NOT NULL CHECK (avaliado_por IN ('video', 'sistema', 'humano')),  -- proposta; confirmar com o Michael
  PRIMARY KEY (modelo, numero)
);

CREATE TABLE ia.opi (
  id               uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  modelo           text NOT NULL REFERENCES ia.opi_modelo (codigo) ON DELETE RESTRICT,
  motorista_id     uuid NOT NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  veiculo_id       uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  semi_id          uuid NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  mes              date NOT NULL CHECK (extract(day FROM mes) = 1),
  tipo             text NOT NULL CHECK (tipo IN ('anunciada', 'nao_anunciada')),
  trecho           tstzrange NOT NULL CHECK (NOT isempty(trecho)),
  local_texto      text NULL,
  itens_avaliados  smallint NULL CHECK (itens_avaliados >= 0),   -- calculados pelo sistema, nunca digitados
  itens_atendidos  smallint NULL CHECK (itens_atendidos >= 0),
  percentual       numeric(5,2) NULL CHECK (percentual BETWEEN 0 AND 100),
  infracao         boolean NULL,
  reincidente      boolean NULL,
  observacao       text NULL CHECK (length(observacao) <= 2000),
  acao_sugerida    text NULL CHECK (acao_sugerida IN ('orientacao', 'advertencia_verbal', 'advertencia_escrita', 'suspensao', 'desligamento', 'nenhuma')),
  acao_decidida    text NULL CHECK (acao_decidida IN ('orientacao', 'advertencia_verbal', 'advertencia_escrita', 'suspensao', 'desligamento', 'nenhuma')),
  estado           text NOT NULL DEFAULT 'gerando' CHECK (estado IN ('gerando', 'aguardando_validacao', 'validada', 'cancelada')),
  validada_por     uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  validada_em      timestamptz NULL,
  video_link       text NULL,
  pdf_arquivo      text NULL,
  criado_em        timestamptz NOT NULL DEFAULT now(),
  CHECK (itens_atendidos IS NULL OR itens_avaliados IS NULL OR itens_atendidos <= itens_avaliados),
  CHECK ((estado = 'validada') = (validada_por IS NOT NULL))
);
-- Uma OPI de condução por motorista por mês (canceladas não contam).
CREATE UNIQUE INDEX opi_motorista_mes_uk ON ia.opi (motorista_id, mes) WHERE estado <> 'cancelada';

CREATE TABLE ia.opi_resposta (
  opi_id      uuid NOT NULL REFERENCES ia.opi (id) ON DELETE RESTRICT,
  modelo      text NOT NULL,
  numero      smallint NOT NULL,
  resposta    text NOT NULL CHECK (resposta IN ('sim', 'nao', 'na')),
  origem      text NOT NULL CHECK (origem IN ('ia', 'humano', 'sistema')),
  evidencia   text NULL CHECK (length(evidencia) <= 1000),
  confianca   text NULL CHECK (confianca IN ('alta', 'media', 'baixa')),
  alterado_por uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  alterado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (opi_id, numero),
  FOREIGN KEY (modelo, numero) REFERENCES ia.opi_modelo_item (modelo, numero) ON DELETE RESTRICT
);

CREATE TABLE ia.consumo (
  id             uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  agente         text NOT NULL CHECK (agente IN ('triagem', 'reanalise', 'opi')),
  modelo         text NOT NULL,
  tokens_entrada integer NOT NULL CHECK (tokens_entrada >= 0),
  tokens_saida   integer NOT NULL CHECK (tokens_saida >= 0),
  tokens_cache   integer NOT NULL DEFAULT 0 CHECK (tokens_cache >= 0),
  custo_usd      numeric(12,6) NOT NULL CHECK (custo_usd >= 0),
  evento_id      uuid NULL REFERENCES derivado.evento (id) ON DELETE RESTRICT,
  opi_id         uuid NULL REFERENCES ia.opi (id) ON DELETE RESTRICT,
  em             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX consumo_mes_ix ON ia.consumo (em);
