-- 004 · Bruto: o que chega da Autotrac e do Moovsec, sem mexer.
-- Tabelas grandes particionadas por mês (horario em UTC). Retenção: 12 meses (parâmetro retencao.meses).
-- Regra: nada do derivado aponta com FK para o bruto, senão apagar uma partição antiga seria bloqueado.
--        O derivado guarda a referência da origem (texto) e o horário.

CREATE TABLE bruto.ingestao_lote (
  id         uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  fonte      text NOT NULL CHECK (fonte IN ('autotrac_posicao', 'autotrac_evento', 'autotrac_macro', 'autotrac_login', 'moovsec_alarme', 'datapar')),
  inicio     timestamptz NOT NULL DEFAULT now(),
  fim        timestamptz NULL,
  cursor_de  text NULL,          -- até onde já tinha buscado
  cursor_ate text NULL,          -- até onde este lote buscou
  linhas     integer NOT NULL DEFAULT 0 CHECK (linhas >= 0),
  estado     text NOT NULL DEFAULT 'rodando' CHECK (estado IN ('rodando', 'ok', 'erro')),
  erro       text NULL CHECK (length(erro) <= 1000)
);
CREATE INDEX ingestao_lote_fonte_ix ON bruto.ingestao_lote (fonte, inicio DESC);

-- Posição a cada ~60 s (celular) ou até 15 min (satélite). ~290 mil linhas/dia.
CREATE TABLE bruto.autotrac_posicao (
  veiculo_id   uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  horario      timestamptz NOT NULL,
  local        geography(Point, 4326) NULL,
  velocidade   numeric(5,1) NULL CHECK (velocidade BETWEEN 0 AND 250),
  ignicao      boolean NULL,
  limpador     boolean NULL,
  odometro_km  numeric(10,1) NULL CHECK (odometro_km >= 0),
  canal        text NULL CHECK (canal IN ('celular', 'satelite')),
  lote_id      uuid NULL,
  recebido_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (veiculo_id, horario)
) PARTITION BY RANGE (horario);
CREATE INDEX autotrac_posicao_horario_ix ON bruto.autotrac_posicao (horario);

-- Eventos de telemetria: freada, força G, excesso, freio motor.
CREATE TABLE bruto.autotrac_evento (
  veiculo_id   uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  horario      timestamptz NOT NULL,
  tipo         text NOT NULL CHECK (tipo ~ '^[a-z_]{2,40}$'),
  valor        numeric NULL,
  local        geography(Point, 4326) NULL,
  velocidade   numeric(5,1) NULL CHECK (velocidade BETWEEN 0 AND 250),
  dados        jsonb NOT NULL DEFAULT '{}',
  lote_id      uuid NULL,
  recebido_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (veiculo_id, horario, tipo)
) PARTITION BY RANGE (horario);

-- Alarmes de câmera. Atenção no parser: lat/long vêm trocadas e com ponto de milhar; motorista e CPF vêm vazios.
CREATE TABLE bruto.moovsec_alarme (
  id_moovsec     text NOT NULL,
  horario        timestamptz NOT NULL,
  placa          text NOT NULL,                                  -- como veio
  veiculo_id     uuid NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,  -- NULL = placa ainda não cadastrada
  tipo           text NOT NULL,                                  -- ex.: bocejando, sem_cinto, distraido
  canal          smallint NULL CHECK (canal BETWEEN 1 AND 16),
  local          geography(Point, 4326) NULL,                    -- já corrigido
  velocidade     numeric(5,1) NULL CHECK (velocidade BETWEEN 0 AND 250),
  duracao_s      numeric(6,1) NULL CHECK (duracao_s >= 0),
  link_clipe     text NULL,
  status_origem  text NULL,
  linha_bruta    jsonb NOT NULL,                                 -- a linha original, para reprocessar
  lote_id        uuid NULL,
  recebido_em    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id_moovsec, horario)
) PARTITION BY RANGE (horario);
CREATE INDEX moovsec_alarme_veiculo_ix ON bruto.moovsec_alarme (veiculo_id, horario);

-- Macros de jornada (volume menor, sem partição).
CREATE TABLE bruto.autotrac_macro (
  id                     uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  veiculo_id             uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  motorista_id           uuid NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  codigo_motorista       text NULL,                              -- como veio da Autotrac
  horario                timestamptz NOT NULL,
  numero                 smallint NOT NULL,                      -- código da macro (lista: documentação da API)
  descricao              text NULL,
  local_texto            text NULL,
  local                  geography(Point, 4326) NULL,
  lote_id                uuid NULL,
  recebido_em            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (veiculo_id, horario, numero)
);
CREATE INDEX autotrac_macro_motorista_ix ON bruto.autotrac_macro (motorista_id, horario);

-- Login e logout do motorista no terminal: é daqui que sai "quem dirigia".
CREATE TABLE bruto.autotrac_login (
  id                uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  veiculo_id        uuid NOT NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  motorista_id      uuid NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  codigo_motorista  text NOT NULL,
  horario           timestamptz NOT NULL,
  tipo              text NOT NULL CHECK (tipo IN ('login', 'logout')),
  lote_id           uuid NULL,
  recebido_em       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (veiculo_id, horario, tipo)
);

-- Cria as partições mensais que faltarem (do mês atual até N meses à frente).
-- Também chamada pelo job diário; idempotente.
CREATE OR REPLACE FUNCTION controle.job_particoes(p_meses_frente integer DEFAULT 2) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  t text; m date; criadas integer := 0; nome text;
BEGIN
  FOREACH t IN ARRAY ARRAY['autotrac_posicao', 'autotrac_evento', 'moovsec_alarme'] LOOP
    FOR i IN -1 .. p_meses_frente LOOP
      m := (date_trunc('month', now() AT TIME ZONE 'UTC') + make_interval(months => i))::date;
      nome := format('%s_%s', t, to_char(m, 'YYYYMM'));
      IF to_regclass(format('bruto.%I', nome)) IS NULL THEN
        EXECUTE format('CREATE TABLE bruto.%I PARTITION OF bruto.%I FOR VALUES FROM (%L) TO (%L)',
          nome, t, (m::timestamp AT TIME ZONE 'UTC'), ((m + interval '1 month')::timestamp AT TIME ZONE 'UTC'));
        criadas := criadas + 1;
      END IF;
    END LOOP;
  END LOOP;
  RETURN criadas;
END $$;

SELECT controle.job_particoes(2);
