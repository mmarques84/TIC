-- Tela de Jornada (spec jornada-painel V1–V7). Transação desfeita no fim. Dados fictícios.
BEGIN;
SET ROLE tic_dono;
\ir ../dados/jornada-ficticio.sql

INSERT INTO acesso.usuario (id, nome, email, perfil, todas_operacoes) VALUES
  ('00000000-0000-7000-8000-00000000d501', 'Operação Teste', 'op.j@exemplo.com', 'operacao', true),
  ('00000000-0000-7000-8000-00000000d502', 'Diretoria Teste', 'dir.j@exemplo.com', 'diretoria', true),
  ('00000000-0000-7000-8000-00000000d503', 'Central Teste', 'cen.j@exemplo.com', 'central', true),
  ('00000000-0000-7000-8000-00000000d504', 'Outra Operação', 'outra.j@exemplo.com', 'operacao', false);
INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES ('00000000-0000-7000-8000-00000000d601', 'outra_j', 'Outra J', 'viagem');
INSERT INTO acesso.usuario_operacao VALUES ('00000000-0000-7000-8000-00000000d504', '00000000-0000-7000-8000-00000000d601');
INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES ('00000000-0000-7000-8000-00000000d602', 'uma_j', 'Uma J', 'viagem');
UPDATE cadastro.motorista SET operacao_id = CASE WHEN id = '00000000-0000-7000-8000-00000000c202'
  THEN '00000000-0000-7000-8000-00000000d601'::uuid ELSE '00000000-0000-7000-8000-00000000d602'::uuid END
WHERE nome LIKE 'Motorista %';

DO $$
DECLARE
  op uuid := '00000000-0000-7000-8000-00000000d501'; dir uuid := '00000000-0000-7000-8000-00000000d502';
  cen uuid := '00000000-0000-7000-8000-00000000d503'; outra uuid := '00000000-0000-7000-8000-00000000d504';
  ma uuid := '00000000-0000-7000-8000-00000000c201'; mh uuid := '00000000-0000-7000-8000-00000000c207';
  l jsonb; d jsonb; r jsonb;
BEGIN
  -- V2 (R3, R5): ordem por nível e contagens
  SELECT motoristas INTO l FROM derivado.sp_jornada_listar(op, NULL, NULL, NULL, false);
  ASSERT jsonb_array_length(l) = 6, 'seis motoristas: ' || jsonb_array_length(l);
  ASSERT l->0->>'nome' = 'Motorista A' AND l->0->>'nivel' = 'violacao', 'A primeiro (violação): ' || (l->0->>'nome');
  ASSERT l->1->>'nivel' = 'conferir' AND l->2->>'nivel' = 'conferir', 'depois conferir';
  ASSERT l->3->>'nome' = 'Motorista G' AND l->3->>'nivel' = 'atencao', 'G em atenção: ' || (l->3->>'nome') || ' ' || (l->3->>'nivel');
  SELECT resumo INTO r FROM derivado.sp_jornada_resumo(op);
  ASSERT (r->>'violacao')::int = 1 AND (r->>'conferir')::int = 2 AND (r->>'atencao')::int = 1, 'resumo: ' || r;
  ASSERT (r->>'jornada')::int >= 3, 'em jornada';

  -- V4 (R6, R7): a linha do A
  ASSERT (l->0->>'diasSemDsr')::int = 7 AND l->0->>'status' = 'dirigindo', 'A: 7 dias e dirigindo';
  ASSERT l->0->'alertas' @> '[{"codigo":"direcao_continua"}]' AND (l->0->'alertas'->0->>'texto') IS NOT NULL, 'alerta com texto';
  ASSERT (SELECT bool_or(m->>'codigo' = 'parado_35h_jornada_aberta') FROM jsonb_array_elements(l) x, jsonb_array_elements(x->'alertas') m
          WHERE x->>'nome' = 'Motorista H'), 'H parado 35 h com jornada aberta';
  ASSERT (SELECT bool_or(m->>'codigo' = 'km_sem_jornada') FROM jsonb_array_elements(l) x, jsonb_array_elements(x->'alertas') m
          WHERE x->>'nome' = 'Motorista J'), 'J rodou sem jornada';
  ASSERT (SELECT x->>'status' FROM jsonb_array_elements(l) x WHERE x->>'nome' = 'Motorista G') = 'refeicao', 'G em refeição';

  -- V3 (R4): filtros
  ASSERT jsonb_array_length((SELECT motoristas FROM derivado.sp_jornada_listar(op, NULL, '7+', NULL, false))) = 1, 'filtro 7+';
  ASSERT jsonb_array_length((SELECT motoristas FROM derivado.sp_jornada_listar(op, NULL, NULL, 'tst9', false))) = 1, 'busca placa';
  ASSERT jsonb_array_length((SELECT motoristas FROM derivado.sp_jornada_listar(op, 'violacao', NULL, NULL, false))) = 1, 'faixa violação';

  -- V5 (R8, R9): detalhe
  SELECT motorista INTO d FROM derivado.sp_jornada_detalhe(op, ma);
  ASSERT jsonb_array_length(d->'jornadas') >= 7, 'jornadas de 8 dias: ' || jsonb_array_length(d->'jornadas');
  ASSERT (SELECT bool_or((m->>'desconhecida')::boolean) FROM jsonb_array_elements(d->'macros') m), 'macro desconhecida marcada';
  ASSERT jsonb_array_length((SELECT motorista->'paradas' FROM derivado.sp_jornada_detalhe(op, mh))) >= 1, 'parada do H';

  -- V1 (R1, R2): permissões e escopo
  BEGIN PERFORM derivado.sp_jornada_listar(cen, NULL, NULL, NULL, false); RAISE EXCEPTION 'central viu';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;
  BEGIN PERFORM derivado.sp_tratativa_criar(dir, mh, NULL, 'dsr_confirmado', NULL, NULL); RAISE EXCEPTION 'diretoria tratou';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;
  ASSERT jsonb_array_length((SELECT motoristas FROM derivado.sp_jornada_listar(outra, NULL, NULL, NULL, false))) = 1, 'outra operação só vê o B';
  BEGIN PERFORM derivado.sp_jornada_detalhe(outra, ma); RAISE EXCEPTION 'viu fora do escopo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'NAO_ENCONTRADO' THEN RAISE; END IF; END;

  -- V6 (R10, R11): tratativa
  BEGIN PERFORM derivado.sp_tratativa_criar(op, mh, NULL, 'outro', '  ', NULL); RAISE EXCEPTION 'outro sem observação';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'OBSERVACAO_OBRIGATORIA' THEN RAISE; END IF; END;
  SELECT motorista INTO d FROM derivado.sp_tratativa_criar(op, mh, NULL, 'dsr_confirmado', 'ficou de DSR no pátio', '10.0.0.5');
  ASSERT NOT (d->'alertas' @> '[{"codigo":"parado_35h_jornada_aberta"}]'), 'conferir sumiu: ' || (d->'alertas');
  ASSERT d->'tratativa'->>'tipo' = 'dsr_confirmado', 'tratativa na linha';

  -- V7 (R12, R14): duas tratativas, a última na linha, as duas no histórico e na auditoria
  PERFORM derivado.sp_tratativa_criar(op, mh, NULL, 'tempo_espera', NULL, NULL);
  SELECT motorista INTO d FROM derivado.sp_jornada_detalhe(op, mh);
  ASSERT d->'tratativa'->>'tipo' = 'tempo_espera' AND jsonb_array_length(d->'tratativas') = 2, 'histórico de tratativas';
  ASSERT (SELECT count(*) FROM controle.auditoria WHERE acao = 'jornada.tratativa' AND usuario_id = op) = 2, 'auditoria';
  ASSERT (SELECT (resumo->>'tratados')::int FROM derivado.sp_jornada_resumo(op)) = 1, 'faixa tratados';
END $$;

RESET ROLE;
DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'derivado.sp_jornada_listar(uuid,text,text,text,boolean)', 'EXECUTE'), 'n8n lista';
  ASSERT has_function_privilege('tic_n8n', 'derivado.sp_tratativa_criar(uuid,uuid,uuid,text,text,inet)', 'EXECUTE'), 'n8n trata';
END $$;
ROLLBACK;
