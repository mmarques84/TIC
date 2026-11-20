-- 002 · Cadastro: operação, base, veículo, conjunto, motorista, cliente; escopo do usuário por operação.
-- Veículo e motorista nascem pela ingestão (Autotrac/Moovsec) e são completados na tela de Admin.

CREATE TABLE cadastro.operacao (
  id         uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  codigo     text NOT NULL UNIQUE CHECK (codigo ~ '^[a-z0-9_]{2,30}$'),
  nome       text NOT NULL,
  tipo       text NOT NULL CHECK (tipo IN ('viagem', 'entrega')),
  ativa      boolean NOT NULL DEFAULT true,
  criado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE acesso.usuario_operacao (
  usuario_id  uuid NOT NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  operacao_id uuid NOT NULL REFERENCES cadastro.operacao (id) ON DELETE RESTRICT,
  PRIMARY KEY (usuario_id, operacao_id)
);

CREATE TABLE cadastro.base (
  id              uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  operacao_id     uuid NOT NULL REFERENCES cadastro.operacao (id) ON DELETE RESTRICT,
  nome            text NOT NULL,
  codigo_externo  text NULL,                                   -- ex.: código Portran/Datapar
  local           geography(Point, 4326) NULL,
  raio_m          integer NOT NULL DEFAULT 500 CHECK (raio_m BETWEEN 50 AND 20000),
  ativa           boolean NOT NULL DEFAULT true,
  UNIQUE (operacao_id, nome)
);

CREATE TABLE cadastro.veiculo (
  id           uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  placa        text NOT NULL UNIQUE CHECK (placa ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'),  -- sem hífen, Mercosul ou antiga
  tipo         text NOT NULL CHECK (tipo IN ('cavalo', 'semi', 'outro')),
  frota        text NULL,
  operacao_id  uuid NULL REFERENCES cadastro.operacao (id) ON DELETE RESTRICT,
  id_autotrac  text NULL UNIQUE,
  serial_dvr   text NULL UNIQUE,                                 -- DVR do Moovsec
  origem       text NOT NULL CHECK (origem IN ('autotrac', 'moovsec', 'planilha', 'manual')),
  ativo        boolean NOT NULL DEFAULT true,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

-- Qual semi vai com qual cavalo, e quando ("RELAÇÃO ATUALIZADA").
CREATE TABLE cadastro.conjunto (
  id        uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  cavalo_id uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  semi_id   uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  periodo   tstzrange NOT NULL CHECK (NOT isempty(periodo) AND lower(periodo) IS NOT NULL),
  origem    text NOT NULL CHECK (origem IN ('planilha', 'manual')),
  CHECK (cavalo_id <> semi_id),
  -- um cavalo não puxa dois semis ao mesmo tempo, nem um semi está em dois cavalos
  EXCLUDE USING gist (cavalo_id WITH =, periodo WITH &&),
  EXCLUDE USING gist (semi_id WITH =, periodo WITH &&)
);

CREATE TABLE cadastro.motorista (
  id                    uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  nome                  text NOT NULL CHECK (length(btrim(nome)) >= 2),
  matricula             text NULL UNIQUE,
  codigo_autotrac       text NULL UNIQUE,
  operacao_id           uuid NULL REFERENCES cadastro.operacao (id) ON DELETE RESTRICT,
  sem_controle_jornada  boolean NOT NULL DEFAULT false,
  origem                text NOT NULL CHECK (origem IN ('autotrac', 'planilha', 'manual')),
  ativo                 boolean NOT NULL DEFAULT true,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  atualizado_em         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX motorista_nome_ix ON cadastro.motorista (lower(nome));

-- Fase 2 (entregas), criado já para não mudar o cadastro depois.
CREATE TABLE cadastro.cliente (
  id          uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  nome        text NOT NULL,
  segmento    text NULL CHECK (segmento IN ('rede', 'empresa')),
  endereco    text NULL,
  local       geography(Point, 4326) NULL,
  raio_m      integer NULL CHECK (raio_m BETWEEN 20 AND 5000),
  observacao  text NULL CHECK (length(observacao) <= 1000),
  ativo       boolean NOT NULL DEFAULT true
);
