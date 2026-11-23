-- Central de alertas (spec central-alertas V1–V9). Transação desfeita no fim. Dados fictícios.
BEGIN;
SET ROLE tic_dono;
\ir ../dados/central-ficticio.sql

INSERT INTO acesso.usuario (id, nome, email, perfil) VALUES
  ('00000000-0000-7000-8000-00000000c501', 'Central Teste', 'central.t@exemplo.com', 'central'),
  ('00000000-0000-7000-8000-00000000c502', 'Diretoria Teste', 'dir.t@exemplo.com', 'diretoria'),
  ('00000000-0000-7000-8000-00000000c503', 'TI Teste', 'ti.t@exemplo.com', 'ti'),
  ('00000000-0000-7000-8000-00000000c504', 'Frota Teste', 'frota.t@exemplo.com', 'frota_opi'),
  ('00000000-0000-7000-8000-00000000c505', 'Outra Operação', 'outra.t@exemplo.com', 'central');
UPDATE acesso.usuario SET todas_operacoes = true WHERE id IN ('00000000-0000-7000-8000-00000000c501', '00000000-0000-7000-8000-00000000c502',
  '00000000-0000-7000-8000-00000000c503', '00000000-0000-7000-8000-00000000c504');
-- c505 só vê a operação "Outra"; os veículos do TST1A01 passam a ser da operação "Uma"
INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES
  ('00000000-0000-7000-8000-00000000c601', 'uma_teste', 'Uma', 'viagem'), ('00000000-0000-7000-8000-00000000c602', 'outra_teste', 'Outra', 'viagem');
UPDATE cadastro.veiculo SET operacao_id = '00000000-0000-7000-8000-00000000c601' WHERE placa = 'TST1A01';
INSERT INTO acesso.usuario_operacao VALUES ('00000000-0000-7000-8000-00000000c505', '00000000-0000-7000-8000-00000000c602');

DO $$
DECLARE
  cen uuid := '00000000-0000-7000-8000-00000000c501'; dir uuid := '00000000-0000-7000-8000-00000000c502';
  ti uuid := '00000000-0000-7000-8000-00000000c503'; fro uuid := '00000000-0000-7000-8000-00000000c504';
  outra uuid := '00000000-0000-7000-8000-00000000c505';
  crit uuid := '00000000-0000-7000-8000-00000000c401'; l jsonb; d jsonb; n integer;
BEGIN
  -- V2 (R3, R4): crítico primeiro, depois grave (mais novo antes), médio, leve
  SELECT alertas INTO l FROM derivado.sp_central_listar(cen, 'abertos', NULL, NULL, NULL);
  ASSERT jsonb_array_length(l) = 5, 'cinco abertos: ' || jsonb_array_length(l);
  ASSERT l->0->>'nivel' = 'critico' AND l->1->>'titulo' = 'Freada brusca + distração' AND l->4->>'nivel' = 'leve', 'ordem da fila';
  ASSERT l->2->>'motorista' IS NULL AND l->0->>'local' = 'BR-277, Balsa Nova/PR', 'motorista ausente e local';
  ASSERT l->0->'ia'->>'resultado' = 'verdadeiro' AND l->0->>'fotoCapa' IS NOT NULL, 'IA e foto na fila';

  -- V3 (R5): filtros e aba de tratados
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'abertos', 'grave', NULL, NULL))) = 2, 'filtro nível';
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'abertos', NULL, NULL, 'tst4'))) = 1, 'busca placa';
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'abertos', NULL, NULL, 'motorista a'))) = 1, 'busca motorista';
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'tratados', NULL, NULL, NULL))) = 1, 'tratados hoje';

  -- R7: resumo
  ASSERT (SELECT (resumo->>'abertos')::int = 5 AND (resumo->>'critico')::int = 1 FROM derivado.sp_central_resumo(cen)), 'resumo';

  -- V1 (R1, R2): TI não vê; diretoria vê mas não trata; escopo por operação
  BEGIN PERFORM derivado.sp_central_listar(ti, 'abertos', NULL, NULL, NULL); RAISE EXCEPTION 'TI viu';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;
  BEGIN PERFORM derivado.sp_alerta_pegar(dir, crit, NULL); RAISE EXCEPTION 'diretoria tratou';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;
  BEGIN PERFORM derivado.sp_alerta_sirene(fro, crit, NULL); RAISE EXCEPTION 'frota acionou';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(outra, 'abertos', NULL, NULL, NULL))) = 4, 'escopo: sem o TST1A01';
  BEGIN PERFORM derivado.sp_alerta_detalhe(outra, crit, NULL); RAISE EXCEPTION 'viu fora do escopo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'NAO_ENCONTRADO' THEN RAISE; END IF; END;

  -- V4 (R8, R9): detalhe com fotos audita imagem.ver
  SELECT alerta INTO d FROM derivado.sp_alerta_detalhe(cen, crit, '10.0.0.9');
  ASSERT jsonb_array_length(d->'fotos') = 5 AND d->>'linkClipe' IS NOT NULL, 'fotos e clipe';
  ASSERT d->>'mensagemPadrao' LIKE 'Atenção: sinais de sono%', 'mensagem padrão do tipo';
  ASSERT jsonb_array_length(d->'historico') = 1, 'histórico 24 h do motorista';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'imagem.ver' AND usuario_id = cen AND entidade_id = crit::text), 'audita imagem.ver';

  -- V5 (R11): assumir e trocar o responsável
  PERFORM derivado.sp_alerta_pegar(cen, crit, NULL);
  ASSERT (SELECT assumido_por = cen AND estado = 'em_tratamento' FROM derivado.alerta WHERE id = crit), 'assumido';
  PERFORM derivado.sp_alerta_pegar(fro, crit, NULL);
  ASSERT (SELECT assumido_por = fro FROM derivado.alerta WHERE id = crit), 'troca de responsável';

  -- V7 (R15, R16, R18): mensagem e sirene não fecham o alerta
  PERFORM derivado.sp_alerta_mensagem(cen, crit, 'Pare e descanse.', NULL);
  PERFORM derivado.sp_alerta_sirene(cen, crit, NULL);
  ASSERT (SELECT count(*) FROM controle.fila_acao WHERE payload->>'alerta_id' = crit::text) = 2, 'duas ações na fila de saída';
  ASSERT (SELECT estado FROM derivado.alerta WHERE id = crit) = 'em_tratamento', 'continua aberto';
  BEGIN PERFORM derivado.sp_alerta_mensagem(cen, crit, repeat('x', 201), NULL); RAISE EXCEPTION 'texto longo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'TEXTO_INVALIDO' THEN RAISE; END IF; END;

  -- V6 (R12–R14): confirmar (IA concordou) e falso (IA discordou), motivo obrigatório, fila esvazia
  PERFORM derivado.sp_alerta_confirmar(cen, crit, 'motorista parou', NULL);
  ASSERT (SELECT validacao FROM ia.triagem WHERE evento_id = '00000000-0000-7000-8000-00000000c301') = 'concordo', 'IA acertou';
  BEGIN PERFORM derivado.sp_alerta_falso(cen, '00000000-0000-7000-8000-00000000c402', '', NULL, NULL); RAISE EXCEPTION 'sem motivo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'MOTIVO_OBRIGATORIO' THEN RAISE; END IF; END;
  PERFORM derivado.sp_alerta_falso(cen, '00000000-0000-7000-8000-00000000c402', 'objeto', 'era um copo', NULL);
  ASSERT (SELECT validacao FROM ia.triagem WHERE evento_id = '00000000-0000-7000-8000-00000000c302') = 'discordo', 'IA errou';
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'abertos', NULL, NULL, NULL))) = 3, 'saíram da fila';
  ASSERT jsonb_array_length((SELECT alertas FROM derivado.sp_central_listar(cen, 'tratados', NULL, NULL, NULL))) = 3, 'foram para tratados';
  BEGIN PERFORM derivado.sp_alerta_confirmar(cen, crit, NULL, NULL); RAISE EXCEPTION 'tratou de novo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'ALERTA_JA_TRATADO' THEN RAISE; END IF; END;

  -- V9 (R21): auditoria
  SELECT count(DISTINCT acao) INTO n FROM controle.auditoria
  WHERE acao IN ('alerta.assumir', 'alerta.confirmar', 'alerta.falso', 'alerta.mensagem', 'alerta.sirene', 'imagem.ver');
  ASSERT n = 6, 'todas as ações auditadas: ' || n;
END $$;

RESET ROLE;
DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'derivado.sp_central_listar(uuid,text,text,text,text)', 'EXECUTE'), 'n8n lista';
  ASSERT NOT has_function_privilege('tic_n8n', 'derivado.int_alerta_acao(uuid,uuid,text,text,inet)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
