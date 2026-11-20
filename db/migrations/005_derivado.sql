-- 005 · Derivado: o que o motor de regras calcula (sem IA) e o que as pessoas fazem com os alertas.

-- Quem dirigia cada veículo em cada instante (a partir de bruto.autotrac_login).
CREATE TABLE derivado.sessao_motorista (
  id            uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  motorista_id  uuid NOT NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  veiculo_id    uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  periodo       tstzrange NOT NULL CHECK (NOT isempty(periodo) AND lower(periodo) IS NOT NULL),  -- fim aberto = ainda logado
  EXCLUDE USING gist (veiculo_id WITH =, periodo WITH &&)
);
CREATE INDEX sessao_motorista_motorista_ix ON derivado.sessao_motorista USING gist (motorista_id, periodo);

CREATE TABLE derivado.jornada (
  id                         uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  motorista_id               uuid NOT NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  fonte                      text NOT NULL CHECK (fonte IN ('autotrac', 'datapar')),
  inicio                     timestamptz NOT NULL,
  fim                        timestamptz NULL,
  amplitude_min              integer NULL CHECK (amplitude_min >= 0),
  direcao_min                integer NULL CHECK (direcao_min >= 0),
  refeicao_min               integer NULL CHECK (refeicao_min >= 0),
  descanso_min               integer NULL CHECK (descanso_min >= 0),
  trabalho_min               integer NULL CHECK (trabalho_min >= 0),
  max_direcao_continua_min   integer NULL CHECK (max_direcao_continua_min >= 0),
  situacao                   text NOT NULL CHECK (situacao IN ('ok', 'em_curso', 'sem_fim', 'inconsistente')),
  calculado_em               timestamptz NOT NULL DEFAULT now(),
  CHECK (fim IS NULL OR fim > inicio),
  UNIQUE (motorista_id, fonte, inicio)
);

CREATE TABLE derivado.parada (
  id              uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  motorista_id    uuid NOT NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  veiculo_id      uuid NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  periodo         tstzrange NOT NULL CHECK (NOT isempty(periodo)),
  local           geography(Point, 4326) NULL,
  local_texto     text NULL,
  houve_jornada_aberta boolean NOT NULL DEFAULT false,
  km_telemetria   numeric(8,1) NULL CHECK (km_telemetria >= 0),
  conta_dsr       boolean NOT NULL DEFAULT false,   -- 35 h+ no raio e sem deslocamento acima do limite
  calculado_em    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX parada_motorista_ix ON derivado.parada USING gist (motorista_id, periodo);

-- Retrato atual de cada motorista (o que a tela de Jornada lê).
CREATE TABLE derivado.motorista_situacao (
  motorista_id   uuid PRIMARY KEY REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  status         text NOT NULL CHECK (status IN ('dirigindo', 'em_jornada', 'em_servico', 'refeicao', 'parada_descanso', 'fora_jornada', 'sem_eventos')),
  veiculo_id     uuid NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  parado_desde   timestamptz NULL,
  local_texto    text NULL,
  ultimo_dsr     timestamptz NULL,
  dias_sem_dsr   smallint NOT NULL DEFAULT 0 CHECK (dias_sem_dsr >= 0),
  alertas        jsonb NOT NULL DEFAULT '[]',     -- [{"codigo":"dsr","nivel":"grave","texto":"..."}]
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);

-- O fato correlacionado: alarme de câmera e/ou telemetria, com veículo, motorista e horário.
CREATE TABLE derivado.evento (
  id            uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  veiculo_id    uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  motorista_id  uuid NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,  -- NULL = ninguém logado
  horario       timestamptz NOT NULL,
  tipo          text NOT NULL CHECK (tipo ~ '^[a-z_]{2,40}$'),       -- ex.: fadiga, sem_cinto, freada_brusca
  origem        text NOT NULL CHECK (origem IN ('moovsec', 'autotrac', 'regra')),
  origem_ref    text[] NOT NULL DEFAULT '{}',                       -- ids na origem (sem FK: ver 004)
  gravidade     text NOT NULL CHECK (gravidade IN ('leve', 'medio', 'grave', 'critico')),
  regra         text NULL,                                          -- chave do parâmetro que disparou
  local         geography(Point, 4326) NULL,
  velocidade    numeric(5,1) NULL CHECK (velocidade BETWEEN 0 AND 250),
  dados         jsonb NOT NULL DEFAULT '{}',
  criado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX evento_horario_ix ON derivado.evento (horario DESC);
CREATE INDEX evento_veiculo_ix ON derivado.evento (veiculo_id, horario DESC);
CREATE INDEX evento_motorista_ix ON derivado.evento (motorista_id, horario DESC);

-- 3 a 5 fotos por evento. O vídeo fica no Moovsec / file server da TIC.
CREATE TABLE derivado.evento_frame (
  id         uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  evento_id  uuid NOT NULL REFERENCES derivado.evento (id) ON DELETE RESTRICT,
  camera     text NOT NULL CHECK (camera IN ('fadiga', 'frontal', 'lateral_direita', 'lateral_esquerda', 'interna', 'outra')),
  instante   timestamptz NOT NULL,
  arquivo    text NOT NULL,     -- caminho no volume de frames da VPS
  UNIQUE (evento_id, camera, instante)
);

CREATE TABLE derivado.alerta (
  id            uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  evento_id     uuid NOT NULL REFERENCES derivado.evento (id) ON DELETE RESTRICT,
  nivel         text NOT NULL CHECK (nivel IN ('leve', 'medio', 'grave', 'critico')),
  estado        text NOT NULL DEFAULT 'aberto' CHECK (estado IN ('aberto', 'em_tratamento', 'confirmado', 'falso_positivo', 'encerrado')),
  tratado_por   uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  tratado_em    timestamptz NULL,
  observacao    text NULL CHECK (length(observacao) <= 1000),
  criado_em     timestamptz NOT NULL DEFAULT now(),
  CHECK ((estado IN ('aberto') AND tratado_por IS NULL) OR estado <> 'aberto')
);
CREATE INDEX alerta_aberto_ix ON derivado.alerta (criado_em DESC) WHERE estado IN ('aberto', 'em_tratamento');

-- Ação na cabine ou na central. solicitada_por NULL = automática (escalonamento).
CREATE TABLE derivado.acao (
  id              uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  alerta_id       uuid NOT NULL REFERENCES derivado.alerta (id) ON DELETE RESTRICT,
  tipo            text NOT NULL CHECK (tipo IN ('mensagem_terminal', 'sirene', 'aviso_central')),
  texto           text NULL CHECK (length(texto) <= 200),
  solicitada_por  uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  solicitada_em   timestamptz NOT NULL DEFAULT now(),
  enviada_em      timestamptz NULL,
  estado          text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'enviada', 'confirmada', 'erro')),
  resposta        text NULL CHECK (length(resposta) <= 500)
);

CREATE TABLE derivado.tratativa (
  id            uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  motorista_id  uuid NOT NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  alerta_id     uuid NULL REFERENCES derivado.alerta (id) ON DELETE RESTRICT,
  jornada_id    uuid NULL REFERENCES derivado.jornada (id) ON DELETE RESTRICT,
  tipo          text NOT NULL CHECK (tipo IN ('dsr_confirmado', 'tempo_espera', 'macro_errada', 'jornada_correta', 'orientado_advertido', 'outro')),
  observacao    text NULL CHECK (length(observacao) <= 1000),
  criado_por    uuid NOT NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  criado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tratativa_motorista_ix ON derivado.tratativa (motorista_id, criado_em DESC);
