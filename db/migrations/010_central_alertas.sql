-- 010 · Central de alertas (spec central-alertas): quem assumiu, motivo do falso positivo, título e textos padrão.

ALTER TABLE derivado.alerta
  ADD COLUMN titulo        text NULL CHECK (length(titulo) <= 120),         -- ex.: "Fadiga: 11 bocejos em 1 h"
  ADD COLUMN assumido_por  uuid NULL REFERENCES acesso.usuario (id) ON DELETE RESTRICT,
  ADD COLUMN assumido_em   timestamptz NULL,
  ADD COLUMN motivo_falso  text NULL CHECK (motivo_falso IN ('gesto', 'objeto', 'imagem_ruim', 'camera_desalinhada', 'outro')),
  ADD CONSTRAINT alerta_falso_tem_motivo CHECK (estado <> 'falso_positivo' OR motivo_falso IS NOT NULL);

CREATE INDEX alerta_tratado_ix ON derivado.alerta (tratado_em DESC) WHERE tratado_em IS NOT NULL;

-- R15: texto pronto da mensagem ao terminal, por tipo de evento (editável; a confirmar com a TIC).
INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('central.mensagem.padrao',       '"Atenção: a central identificou um alerta no seu veículo. Dirija com segurança."', NULL, 'Mensagem ao terminal quando o tipo não tem texto próprio', 'Spec central-alertas R15'),
  ('central.mensagem.fadiga',       '"Atenção: sinais de sono detectados. Pare no próximo local seguro e descanse."', NULL, 'Mensagem ao terminal para fadiga', 'Spec central-alertas R15'),
  ('central.mensagem.celular',      '"Atenção: uso de celular detectado com o veículo em movimento. Guarde o aparelho."', NULL, 'Mensagem ao terminal para celular', 'Spec central-alertas R15'),
  ('central.mensagem.sem_cinto',    '"Atenção: use o cinto de segurança."', NULL, 'Mensagem ao terminal para sem cinto', 'Spec central-alertas R15'),
  ('central.mensagem.velocidade',   '"Atenção: velocidade acima do limite. Reduza agora."', NULL, 'Mensagem ao terminal para velocidade', 'Spec central-alertas R15'),
  ('central.mensagem.freada_brusca','"Atenção: freada brusca registrada. Mantenha distância segura."', NULL, 'Mensagem ao terminal para freada brusca', 'Spec central-alertas R15'),
  ('central.mensagem.distracao',    '"Atenção: mantenha a atenção na estrada."', NULL, 'Mensagem ao terminal para distração', 'Spec central-alertas R15');
