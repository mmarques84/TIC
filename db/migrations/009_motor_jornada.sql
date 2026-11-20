-- 009 · Motor de jornada (spec motor-jornada): mapa de macros, colunas de resultado e parâmetros.

-- R1, R2: tradução de cada código de macro de cada fonte. Nada de código fixo no cálculo.
CREATE TABLE controle.macro_mapa (
  fonte        text NOT NULL CHECK (fonte IN ('autotrac', 'datapar')),
  numero       smallint NOT NULL,
  significado  text NOT NULL CHECK (significado IN ('inicio_jornada', 'fim_jornada', 'inicio_refeicao', 'fim_refeicao',
                                                    'inicio_parada', 'fim_parada', 'inicio_espera', 'fim_espera', 'ignorar')),
  descricao    text NULL,
  alterado_por uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  alterado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fonte, numero)
);

-- R2: só o que é conhecido (painel Jornada Ipiranga). Autotrac entra com a documentação.
INSERT INTO controle.macro_mapa (fonte, numero, significado, descricao) VALUES
  ('datapar', 1, 'inicio_jornada', 'Início de jornada'),
  ('datapar', 2, 'inicio_refeicao', 'Início de refeição'),
  ('datapar', 7, 'fim_refeicao', 'Fim de refeição'),
  ('datapar', 5, 'inicio_parada', 'Início de parada'),
  ('datapar', 3, 'fim_jornada', 'Fim de jornada');

-- Resultado do motor na jornada (colunas novas; aditivo).
ALTER TABLE derivado.jornada
  ADD COLUMN veiculo_id        uuid NULL REFERENCES cadastro.veiculo (id) ON DELETE RESTRICT,
  ADD COLUMN dia               date NULL,                 -- dia (São Paulo) em que começou
  ADD COLUMN espera_min        integer NULL CHECK (espera_min >= 0),
  ADD COLUMN interjornada_min  integer NULL CHECK (interjornada_min >= 0),  -- desde o fim da jornada anterior
  ADD COLUMN nivel             text NULL CHECK (nivel IN ('dentro', 'atencao', 'violacao')),
  ADD COLUMN motivos           jsonb NOT NULL DEFAULT '[]';
CREATE INDEX jornada_motorista_dia_ix ON derivado.jornada (motorista_id, dia);

-- Situação atual: contadores da semana e macros desconhecidas.
ALTER TABLE derivado.motorista_situacao
  ADD COLUMN jornada_atual_id   uuid NULL REFERENCES derivado.jornada (id) ON DELETE RESTRICT,
  ADD COLUMN trabalho_semana_min integer NOT NULL DEFAULT 0 CHECK (trabalho_semana_min >= 0),
  ADD COLUMN macros_desconhecidas integer NOT NULL DEFAULT 0 CHECK (macros_desconhecidas >= 0),
  ADD COLUMN nivel              text NOT NULL DEFAULT 'dentro' CHECK (nivel IN ('dentro', 'atencao', 'violacao', 'conferir'));

-- R22: um evento por ocorrência, mesmo com recálculo (chave de idempotência).
ALTER TABLE derivado.evento ADD COLUMN chave text NULL;
CREATE UNIQUE INDEX evento_chave_uk ON derivado.evento (chave) WHERE chave IS NOT NULL;

-- R10–R16: limites (globais; valores por operação entram quando as operações forem cadastradas).
INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('jornada.atencao_dia',          '10', 'h',   'Trabalho líquido no dia acima disso: atenção', 'Spec motor-jornada R10/R14'),
  ('jornada.limite_dia',           '12', 'h',   'Trabalho líquido no dia acima disso: violação', 'Spec motor-jornada R10/R14'),
  ('jornada.aberta_max',           '13', 'h',   'Jornada aberta há mais que isso: violação', 'Spec motor-jornada R10'),
  ('jornada.atencao_semana',       '52', 'h',   'Trabalho na semana a partir disso: atenção', 'Spec motor-jornada R11/R14'),
  ('jornada.limite_semana',        '60', 'h',   'Trabalho na semana acima disso: violação', 'Spec motor-jornada R11/R14'),
  ('jornada.refeicao_max',         '120','min', 'Refeição que passar disso volta a contar como jornada', 'Spec motor-jornada R6'),
  ('jornada.em_curso_max',         '16', 'h',   'Sem fim há até este tempo: em curso; depois: sem fim', 'Spec motor-jornada R8'),
  ('jornada.inconsistente',        '18', 'h',   'Início e fim mais distantes que isso: inconsistente', 'Spec motor-jornada R9'),
  ('jornada.dias_sem_dsr.atencao', '6',  'dias','Dias sem DSR a partir disso: atenção', 'Spec motor-jornada R16'),
  ('parada.minima',                '11', 'h',   'Parada no mesmo lugar a partir disso é parada longa', 'Spec motor-jornada R15'),
  ('telemetria.parado_kmh',        '3',  'km/h','Velocidade até isso conta como parado', 'Spec motor-jornada R7'),
  ('telemetria.intervalo_max',     '20', 'min', 'Buraco entre posições maior que isso não conta como direção', 'Spec motor-jornada R7');
