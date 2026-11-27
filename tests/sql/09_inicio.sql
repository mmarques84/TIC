-- Início com dados reais (spec inicio-resumo V1–V6). Transação desfeita no fim. Tudo fictício.
BEGIN;
SET ROLE tic_dono;

-- V6 (R14): banco sem dados → abre sem erro e sem número de exemplo
DO $$ DECLARE u uuid; r jsonb; BEGIN
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('Admin Vazio', 'vazio@teste.local', 'admin', true) RETURNING id INTO u;
  SELECT resumo INTO r FROM controle.sp_inicio_resumo(u);
  ASSERT jsonb_array_length(r->'alertas') = 0, 'sem alertas';
  ASSERT (SELECT i->>'nota' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'alertas') = 'aguardando a correlação de alertas', 'motivo escrito';
  ASSERT (SELECT i->>'valor' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'consumo_ia') = '—', 'sem teto = —';
END $$;

INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES
  ('00000000-0000-7000-8000-0000000000a1', 'op_a', 'Operação A (teste)', 'entrega'),
  ('00000000-0000-7000-8000-0000000000a2', 'op_b', 'Operação B (teste)', 'entrega');
INSERT INTO cadastro.veiculo (id, placa, tipo, origem, operacao_id) VALUES
  ('00000000-0000-7000-8000-00000000f001', 'TST1A11', 'cavalo', 'manual', '00000000-0000-7000-8000-0000000000a1'),
  ('00000000-0000-7000-8000-00000000f002', 'TST2B22', 'cavalo', 'manual', '00000000-0000-7000-8000-0000000000a2');
INSERT INTO derivado.evento (id, veiculo_id, horario, tipo, origem, gravidade) VALUES
  ('00000000-0000-7000-8000-00000000f101', '00000000-0000-7000-8000-00000000f001', now() - interval '20 min', 'freada_brusca', 'autotrac', 'grave'),
  ('00000000-0000-7000-8000-00000000f102', '00000000-0000-7000-8000-00000000f001', now() - interval '5 min', 'fadiga', 'moovsec', 'critico'),
  ('00000000-0000-7000-8000-00000000f103', '00000000-0000-7000-8000-00000000f002', now() - interval '40 min', 'velocidade', 'autotrac', 'medio');
INSERT INTO derivado.alerta (evento_id, nivel, criado_em) VALUES
  ('00000000-0000-7000-8000-00000000f101', 'grave', now() - interval '20 min'),
  ('00000000-0000-7000-8000-00000000f102', 'critico', now() - interval '5 min'),
  ('00000000-0000-7000-8000-00000000f103', 'medio', now() - interval '40 min');

UPDATE controle.credencial_status SET ultimo_sucesso = now() - interval '5 min', senha_mudou = false WHERE fonte = 'autotrac';
UPDATE controle.credencial_status SET ultimo_sucesso = now() - interval '2 hours', senha_mudou = false WHERE fonte = 'claude';
UPDATE controle.credencial_status SET ultimo_erro = 'HTTP 401', ultimo_erro_em = now(), senha_mudou = true WHERE fonte = 'datapar';
UPDATE controle.credencial_status SET ultimo_sucesso = NULL, ultimo_erro = NULL WHERE fonte = 'moovsec';

DO $$ DECLARE adm uuid; ti uuid; opb uuid; r jsonb; BEGIN
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('Admin Teste', 'adm@teste.local', 'admin', true) RETURNING id INTO adm;
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('TI Teste', 'ti@teste.local', 'ti', true) RETURNING id INTO ti;
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('Operação B', 'opb@teste.local', 'operacao', false) RETURNING id INTO opb;
  INSERT INTO acesso.usuario_operacao (usuario_id, operacao_id) VALUES (opb, '00000000-0000-7000-8000-0000000000a2');

  -- V2, V5 (R3, R11): contagem e ordem (crítico antes de grave; no nível, o mais antigo)
  SELECT resumo INTO r FROM controle.sp_inicio_resumo(adm);
  ASSERT (SELECT i->>'valor' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'alertas') = '3', 'três abertos';
  ASSERT (SELECT i->>'nota' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'alertas') = '1 crítico(s)', 'um crítico';
  ASSERT r->'alertas'->0->>'nivel' = 'critico' AND r->'alertas'->1->>'nivel' = 'grave' AND r->'alertas'->2->>'nivel' = 'medio', 'ordem: ' || (r->'alertas');
  ASSERT r->'alertas'->0->>'placa' = 'TST1A11' AND r->'alertas'->0->>'ha' LIKE 'há % min', 'placa e há X min';
  ASSERT (SELECT i->>'valor' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'fadiga') = '1', 'fadiga na última hora';

  -- V4 (R10, R12): estado de cada integração
  ASSERT (SELECT i->>'estado' FROM jsonb_array_elements(r->'integracoes') i WHERE i->>'fonte' = 'Autotrac · Telemetria') = 'ok', 'autotrac ok';
  ASSERT (SELECT i->>'texto' FROM jsonb_array_elements(r->'integracoes') i WHERE i->>'fonte' = 'Autotrac · Telemetria') LIKE 'último dado há 5 min · % eventos hoje', 'texto autotrac';
  ASSERT (SELECT i->>'estado' FROM jsonb_array_elements(r->'integracoes') i WHERE i->>'fonte' = 'IA (Claude)') = 'atraso', 'claude atraso';
  ASSERT (SELECT i->>'estado' FROM jsonb_array_elements(r->'integracoes') i WHERE i->>'fonte' = 'Datapar') = 'erro', 'datapar erro';
  ASSERT (SELECT i->>'estado' FROM jsonb_array_elements(r->'integracoes') i WHERE i->>'fonte' = 'Moovsec') = 'inativa', 'moovsec inativa';

  -- V1 (R1): TI não recebe alertas
  SELECT resumo INTO r FROM controle.sp_inicio_resumo(ti);
  ASSERT jsonb_array_length(r->'alertas') = 0, 'TI sem alertas';
  ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'alertas'), 'TI sem indicador de alertas';
  ASSERT jsonb_array_length(r->'integracoes') = 5, 'TI vê integrações';

  -- V1 (R2): operação B só vê o alerta do veículo da operação B
  SELECT resumo INTO r FROM controle.sp_inicio_resumo(opb);
  ASSERT jsonb_array_length(r->'alertas') = 1 AND r->'alertas'->0->>'placa' = 'TST2B22', 'escopo da operação';
  ASSERT jsonb_array_length(r->'integracoes') = 0, 'operação não vê integrações';

  -- V3 (R7): sem triagem hoje = —
  ASSERT (SELECT i->>'valor' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'falsos_evitados') IS NULL
      OR (SELECT i->>'valor' FROM jsonb_array_elements(r->'indicadores') i WHERE i->>'codigo' = 'falsos_evitados') = '—', 'sem triagem';
END $$;

DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'controle.sp_inicio_resumo(uuid)', 'EXECUTE'), 'n8n lê o resumo';
END $$;
ROLLBACK;
