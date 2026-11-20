-- 001 · Schemas, UUID v7, acesso (usuários, perfis, sessões) e auditoria.
-- Roda como tic_dono, numa transação (scripts/migrar.sh). Só aditiva.

CREATE SCHEMA IF NOT EXISTS acesso;
CREATE SCHEMA IF NOT EXISTS cadastro;
CREATE SCHEMA IF NOT EXISTS bruto;
CREATE SCHEMA IF NOT EXISTS derivado;
CREATE SCHEMA IF NOT EXISTS ia;
CREATE SCHEMA IF NOT EXISTS controle;

COMMENT ON SCHEMA acesso   IS 'Usuários, perfis, permissões, sessões';
COMMENT ON SCHEMA cadastro IS 'Operação, base, veículo, conjunto, motorista, cliente';
COMMENT ON SCHEMA bruto    IS 'Dados como chegam das fontes (Autotrac, Moovsec). Eventos grandes particionados por mês';
COMMENT ON SCHEMA derivado IS 'Calculado pelo motor de regras: sessão do motorista, jornada, evento, alerta, ação, tratativa';
COMMENT ON SCHEMA ia       IS 'Triagem, OPI e consumo da IA';
COMMENT ON SCHEMA controle IS 'Parâmetros, auditoria, fila de ações, status das integrações';

-- UUID v7: ordenado pelo tempo (índices mais compactos que o v4).
CREATE OR REPLACE FUNCTION controle.uuid_v7() RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  ms bigint := floor(extract(epoch FROM clock_timestamp()) * 1000);
  b  bytea  := substring(int8send(ms) FROM 3) || public.gen_random_bytes(10);
BEGIN
  b := set_byte(b, 6, (get_byte(b, 6) & 15) | 112);  -- versão 7
  b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);  -- variante RFC 9562
  RETURN encode(b, 'hex')::uuid;
END $$;

-- ===== acesso =====

CREATE TABLE acesso.perfil (
  codigo    text PRIMARY KEY CHECK (codigo ~ '^[a-z_]{2,30}$'),
  nome      text NOT NULL,
  descricao text NOT NULL
);

CREATE TABLE acesso.permissao (
  codigo    text PRIMARY KEY CHECK (codigo ~ '^[a-z_]+\.[a-z_]+$'),  -- recurso.operacao
  descricao text NOT NULL
);

CREATE TABLE acesso.perfil_permissao (
  perfil    text NOT NULL REFERENCES acesso.perfil (codigo) ON DELETE RESTRICT,
  permissao text NOT NULL REFERENCES acesso.permissao (codigo) ON DELETE RESTRICT,
  PRIMARY KEY (perfil, permissao)
);

CREATE TABLE acesso.usuario (
  id                 uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  nome               text NOT NULL CHECK (length(btrim(nome)) BETWEEN 2 AND 120),
  email              text NOT NULL CHECK (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  perfil             text NOT NULL REFERENCES acesso.perfil (codigo) ON DELETE RESTRICT,
  todas_operacoes    boolean NOT NULL DEFAULT false,  -- false = só as de acesso.usuario_operacao
  senha_hash         text NULL CHECK (senha_hash IS NULL OR senha_hash LIKE 'pbkdf2$%'),
  ativo              boolean NOT NULL DEFAULT true,
  tentativas_falhas  smallint NOT NULL DEFAULT 0 CHECK (tentativas_falhas >= 0),
  bloqueado_ate      timestamptz NULL,
  criado_em          timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT usuario_email_uk UNIQUE (email)
);

CREATE TABLE acesso.sessao (
  id             uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  usuario_id     uuid NOT NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  token_hash     char(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),  -- SHA-256 do cookie
  csrf_hash      char(64) NOT NULL CHECK (csrf_hash ~ '^[0-9a-f]{64}$'),
  criada_em      timestamptz NOT NULL DEFAULT now(),
  ultimo_uso_em  timestamptz NOT NULL DEFAULT now(),
  expira_em      timestamptz NOT NULL,
  revogada_em    timestamptz NULL,
  ip             inet NULL,
  user_agent     text NULL CHECK (length(user_agent) <= 400),
  CHECK (expira_em > criada_em)
);
CREATE INDEX sessao_usuario_ix ON acesso.sessao (usuario_id) WHERE revogada_em IS NULL;

CREATE TABLE acesso.definicao_senha (
  id           uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  usuario_id   uuid NOT NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  token_hash   char(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  tipo         text NOT NULL CHECK (tipo IN ('convite', 'recuperacao')),
  criado_por   uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,  -- NULL = pedido pelo próprio usuário
  criado_em    timestamptz NOT NULL DEFAULT now(),
  expira_em    timestamptz NOT NULL,
  usado_em     timestamptz NULL,
  CHECK (expira_em > criado_em),
  CHECK (usado_em IS NULL OR usado_em >= criado_em)
);

-- ===== auditoria (append-only) =====

CREATE TABLE controle.auditoria (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  em           timestamptz NOT NULL DEFAULT now(),
  usuario_id   uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,  -- NULL = sistema (rotina)
  acao         text NOT NULL CHECK (acao ~ '^[a-z_]+\.[a-z_]+$'),             -- ex.: alerta.confirmar, imagem.ver
  entidade     text NOT NULL,
  entidade_id  text NULL,
  antes        jsonb NULL,
  depois       jsonb NULL,
  ip           inet NULL
);
CREATE INDEX auditoria_entidade_ix ON controle.auditoria (entidade, entidade_id);
CREATE INDEX auditoria_usuario_ix ON controle.auditoria (usuario_id, em DESC);

CREATE OR REPLACE FUNCTION controle.int_auditoria_imutavel() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'AUDITORIA_IMUTAVEL' USING ERRCODE = 'P0001',
    DETAIL = 'A auditoria só aceita INSERT.';
END $$;

CREATE TRIGGER auditoria_sem_update BEFORE UPDATE OR DELETE ON controle.auditoria
  FOR EACH ROW EXECUTE FUNCTION controle.int_auditoria_imutavel();
CREATE TRIGGER auditoria_sem_truncate BEFORE TRUNCATE ON controle.auditoria
  FOR EACH STATEMENT EXECUTE FUNCTION controle.int_auditoria_imutavel();
