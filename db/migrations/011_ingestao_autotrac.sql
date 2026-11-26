-- 011 · Ingestão da Autotrac (spec ingestao-autotrac): mapa de eventos, fila de saneamento, motorista no evento, parâmetros.

-- R12: tradução do número/nome do evento de cada fonte para o tipo interno. Nada de código fixo no cálculo.
CREATE TABLE controle.evento_mapa (
  fonte        text NOT NULL CHECK (fonte IN ('autotrac_telemetria', 'autotrac_sds', 'moovsec')),
  chave        text NOT NULL CHECK (length(btrim(chave)) BETWEEN 1 AND 120),   -- número ou nome do evento como vem da fonte
  tipo         text NOT NULL CHECK (tipo ~ '^[a-z_]{2,40}$'),
  descricao    text NULL,
  alterado_por uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  alterado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fonte, chave)
);

-- Eventos de telemetria documentados pela Autotrac (API de Telemetria, recurso telemetryevents).
-- Gravidade e quais viram alerta ficam em aberto (spec ingestao-autotrac, "Em aberto").
INSERT INTO controle.evento_mapa (fonte, chave, tipo, descricao) VALUES
  ('autotrac_telemetria', '1',  'temporizado',                'Temporizado'),
  ('autotrac_telemetria', '2',  'aceleracao_brusca',          'Acelerações bruscas'),
  ('autotrac_telemetria', '4',  'freada_brusca',              'Freadas bruscas'),
  ('autotrac_telemetria', '6',  'partida_frio',               'Partidas a frio'),
  ('autotrac_telemetria', '8',  'banguela',                   'Banguela'),
  ('autotrac_telemetria', '10', 'fora_faixa_verde',           'Fora da faixa verde'),
  ('autotrac_telemetria', '12', 'ignicao_ligada',             'Ignição ligada'),
  ('autotrac_telemetria', '13', 'ignicao_desligada',          'Ignição desligada'),
  ('autotrac_telemetria', '14', 'rpm_excessiva',              'RPM excessiva'),
  ('autotrac_telemetria', '16', 'velocidade_excessiva',       'Velocidade excessiva'),
  ('autotrac_telemetria', '18', 'velocidade_excessiva_chuva', 'Velocidade excessiva na chuva'),
  ('autotrac_telemetria', '20', 'marcha_lenta_excessiva',     'Marcha lenta excessiva'),
  ('autotrac_telemetria', '22', 'pressao_oleo_baixa',         'Baixa pressão do óleo do motor'),
  ('autotrac_telemetria', '24', 'pressao_oleo_alta',          'Alta pressão do óleo do motor');

-- R6–R8, R12, R14: o que não casou com o cadastro. Nada some: fica aqui até alguém resolver (tela Admin · Integrações).
CREATE TABLE controle.saneamento (
  id             uuid PRIMARY KEY DEFAULT controle.uuid_v7(),
  fonte          text NOT NULL CHECK (fonte IN ('autotrac', 'moovsec', 'datapar', 'rodopar')),
  motivo         text NOT NULL CHECK (motivo IN ('placa_sem_cadastro', 'veiculo_sem_placa', 'veiculo_anotado', 'placa_duplicada',
                                                 'codigo_em_conflito', 'tipo_evento_sem_mapa', 'motorista_sem_cadastro')),
  chave          text NOT NULL CHECK (length(chave) <= 200),     -- o que identifica o item na fonte (código, placa, número do evento)
  descricao      text NOT NULL CHECK (length(descricao) <= 300),
  dados          jsonb NOT NULL DEFAULT '{}',
  vezes          integer NOT NULL DEFAULT 1 CHECK (vezes >= 1),
  primeiro_em    timestamptz NOT NULL DEFAULT now(),
  ultimo_em      timestamptz NOT NULL DEFAULT now(),
  estado         text NOT NULL DEFAULT 'aberto' CHECK (estado IN ('aberto', 'resolvido', 'ignorado')),
  resolvido_por  uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  resolvido_em   timestamptz NULL
);
CREATE UNIQUE INDEX saneamento_aberto_ux ON controle.saneamento (fonte, motivo, chave) WHERE estado = 'aberto';

-- R14: quem dirigia no evento da Autotrac (o código como veio e, quando conhecido, o motorista). R11: id do evento na origem.
ALTER TABLE bruto.autotrac_evento
  ADD COLUMN motorista_id     uuid NULL REFERENCES cadastro.motorista (id) ON DELETE RESTRICT,
  ADD COLUMN codigo_motorista text NULL,
  ADD COLUMN origem_id        text NULL;

-- R20: o lote da frota (cadastro) também é registrado.
ALTER TABLE bruto.ingestao_lote DROP CONSTRAINT ingestao_lote_fonte_check;
ALTER TABLE bruto.ingestao_lote ADD CONSTRAINT ingestao_lote_fonte_check
  CHECK (fonte IN ('autotrac_posicao', 'autotrac_evento', 'autotrac_macro', 'autotrac_login', 'autotrac_cadastro', 'moovsec_alarme', 'datapar'));

-- R3: quando foi a última resposta 401/403 (a senha mudou ou o acesso caiu).
ALTER TABLE controle.credencial_status ADD COLUMN ultimo_http smallint NULL;

-- Parâmetros da ingestão (spec ingestao-autotrac R4, R9, R10, R21). Conta da Autotrac não é segredo: é configuração.
INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('autotrac.conta_telemetria',         '10534', NULL,  'Código da conta da TIC na API de Telemetria da Autotrac', 'Spec ingestao-autotrac'),
  ('autotrac.cadastro.intervalo_min',   '60',    'min', 'De quanto em quanto tempo a frota é buscada', 'Spec ingestao-autotrac R4'),
  ('autotrac.telemetria.intervalo_min', '5',     'min', 'De quanto em quanto tempo os eventos são buscados', 'Spec ingestao-autotrac R9'),
  ('autotrac.telemetria.sobreposicao_min', '10', 'min', 'Quanto tempo antes do último evento recebido a busca recomeça', 'Spec ingestao-autotrac R9'),
  ('autotrac.telemetria.inicio_h',      '24',    'h',   'Quanto buscar para trás na primeira vez de um veículo', 'Spec ingestao-autotrac R9'),
  ('autotrac.janela_max_h',             '24',    'h',   'Tamanho máximo de cada chamada (a Autotrac aceita até 72 h)', 'Spec ingestao-autotrac R10'),
  ('autotrac.retencao_dias',            '7',     'dia', 'Quantos dias a Autotrac guarda', 'Spec ingestao-autotrac R10'),
  ('autotrac.alerta_sem_dados_min',     '30',    'min', 'Sem sucesso há mais que isso: aviso de "Autotrac sem dados"', 'Spec ingestao-autotrac R21');
