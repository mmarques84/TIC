-- 003 · Controle: parâmetros das regras (com escopo e vigência), status das integrações, fila de ações.

-- Todo limite de regra mora aqui, nunca no código ou no prompt.
-- operacao_id NULL = vale para todas; uma linha da operação sobrepõe a global.
CREATE TABLE controle.parametro (
  id            uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  chave         text NOT NULL CHECK (chave ~ '^[a-z_]+(\.[a-z_0-9]+)+$'),
  valor         jsonb NOT NULL,
  unidade       text NULL,
  descricao     text NOT NULL,
  operacao_id   uuid NULL REFERENCES cadastro.operacao (id) ON DELETE RESTRICT,
  vigencia      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  alterado_por  uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,  -- NULL = carga inicial
  motivo        text NULL,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT isempty(vigencia)),
  -- nunca dois valores vigentes ao mesmo tempo para a mesma chave e escopo
  EXCLUDE USING gist (
    chave WITH =,
    (coalesce(operacao_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
    vigencia WITH &&
  )
);

CREATE TABLE controle.credencial_status (
  fonte           text PRIMARY KEY CHECK (fonte IN ('autotrac', 'moovsec', 'datapar', 'portran', 'claude')),
  ultimo_sucesso  timestamptz NULL,
  ultimo_erro_em  timestamptz NULL,
  ultimo_erro     text NULL CHECK (length(ultimo_erro) <= 500),
  senha_mudou     boolean NOT NULL DEFAULT false,
  atualizado_em   timestamptz NOT NULL DEFAULT now()
);

-- O banco nunca chama serviço externo: grava aqui e o n8n (adaptador de saída) executa.
CREATE TABLE controle.fila_acao (
  id             uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  tipo           text NOT NULL CHECK (tipo IN ('mensagem_terminal', 'sirene', 'ia_triagem', 'ia_opi', 'email')),
  referencia_id  uuid NULL,                 -- alerta, evento ou opi
  payload        jsonb NOT NULL DEFAULT '{}',
  estado         text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'processando', 'feito', 'erro', 'cancelado')),
  tentativas     smallint NOT NULL DEFAULT 0 CHECK (tentativas BETWEEN 0 AND 20),
  disponivel_em  timestamptz NOT NULL DEFAULT now(),
  criado_em      timestamptz NOT NULL DEFAULT now(),
  processado_em  timestamptz NULL,
  erro           text NULL CHECK (length(erro) <= 1000)
);
CREATE INDEX fila_acao_pendente_ix ON controle.fila_acao (disponivel_em) WHERE estado = 'pendente';
