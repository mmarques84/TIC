-- Estrutura e domínio. Tudo numa transação desfeita no fim. Dados fictícios.
BEGIN;
SET ROLE tic_dono;

-- UUID v7: versão 7 no 13º caractere hexadecimal
DO $$ BEGIN
  ASSERT substr(controle.uuid_v7()::text, 15, 1) = '7', 'uuid_v7 sem versão 7';
END $$;

-- Partições do mês atual existem nas 3 tabelas grandes
DO $$ DECLARE m text := to_char(now() AT TIME ZONE 'UTC', 'YYYYMM'); BEGIN
  ASSERT to_regclass('bruto.autotrac_posicao_' || m) IS NOT NULL, 'falta partição de posição';
  ASSERT to_regclass('bruto.autotrac_evento_' || m) IS NOT NULL, 'falta partição de evento';
  ASSERT to_regclass('bruto.moovsec_alarme_' || m) IS NOT NULL, 'falta partição de alarme';
END $$;

-- Carga inicial
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM acesso.perfil) = 6, 'perfis';
  ASSERT (SELECT count(*) FROM ia.opi_modelo_item WHERE modelo = 'FFRO005-R5') = 42, 'OPI deve ter 42 itens';
  ASSERT NOT EXISTS (SELECT 1 FROM ia.opi_modelo_item WHERE numero = 36), 'item 36 não existe no formulário';
  ASSERT (SELECT count(*) FROM acesso.perfil_permissao WHERE perfil = 'admin') = (SELECT count(*) FROM acesso.permissao), 'admin tem tudo';
END $$;

-- Parâmetro e nível de velocidade
DO $$ BEGIN
  ASSERT controle.fn_parametro_num('fadiga.bocejos_hora.critico') = 10, 'parametro numérico';
  ASSERT controle.fn_nivel_velocidade(80, false) IS NULL, '80 seca = sem excesso';
  ASSERT controle.fn_nivel_velocidade(82, false) = 'leve', '82 seca = leve';
  ASSERT controle.fn_nivel_velocidade(86, false) = 'medio', '86 seca = medio';
  ASSERT controle.fn_nivel_velocidade(87, false) = 'grave', '87 seca = grave';
  ASSERT controle.fn_nivel_velocidade(65, true) = 'medio', '65 molhada = medio';
END $$;

-- Parâmetro da operação vence o global; dois vigentes iguais são recusados
INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES ('00000000-0000-7000-8000-000000000001', 'ipiranga', 'Entrega Ipiranga', 'entrega');
INSERT INTO controle.parametro (chave, valor, unidade, descricao, operacao_id)
VALUES ('jornada.normal', '10', 'h', 'teste', '00000000-0000-7000-8000-000000000001');
DO $$ BEGIN
  ASSERT controle.fn_parametro_num('jornada.normal', '00000000-0000-7000-8000-000000000001') = 10, 'operação vence';
  ASSERT controle.fn_parametro_num('jornada.normal') = 8, 'global continua';
  BEGIN
    INSERT INTO controle.parametro (chave, valor, descricao) VALUES ('jornada.normal', '9', 'duplicado');
    RAISE EXCEPTION 'deveria recusar parâmetro sobreposto';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
END $$;

-- Auditoria só aceita INSERT
INSERT INTO controle.auditoria (acao, entidade) VALUES ('teste.inserir', 'teste');
DO $$ BEGIN
  BEGIN
    UPDATE controle.auditoria SET entidade = 'x';
    RAISE EXCEPTION 'deveria recusar UPDATE';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'AUDITORIA_IMUTAVEL' THEN RAISE; END IF;
  END;
END $$;

-- Conjunto: um cavalo não puxa dois semis ao mesmo tempo
INSERT INTO cadastro.veiculo (id, placa, tipo, origem) VALUES
  ('00000000-0000-7000-8000-0000000000a1', 'TST1A01', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-0000000000a2', 'TST1A02', 'semi', 'manual'),
  ('00000000-0000-7000-8000-0000000000a3', 'TST1A03', 'semi', 'manual');
INSERT INTO cadastro.conjunto (cavalo_id, semi_id, periodo, origem)
VALUES ('00000000-0000-7000-8000-0000000000a1', '00000000-0000-7000-8000-0000000000a2', tstzrange('2026-11-01', NULL), 'manual');
DO $$ BEGIN
  BEGIN
    INSERT INTO cadastro.conjunto (cavalo_id, semi_id, periodo, origem)
    VALUES ('00000000-0000-7000-8000-0000000000a1', '00000000-0000-7000-8000-0000000000a3', tstzrange('2026-11-10', NULL), 'manual');
    RAISE EXCEPTION 'deveria recusar conjunto sobreposto';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
END $$;

-- Placa fora do padrão é recusada
DO $$ BEGIN
  BEGIN
    INSERT INTO cadastro.veiculo (placa, tipo, origem) VALUES ('TST-1A01', 'cavalo', 'manual');
    RAISE EXCEPTION 'deveria recusar placa com hífen';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- Posição cai na partição do mês e alarme com placa desconhecida é aceito (veiculo_id NULL)
INSERT INTO bruto.autotrac_posicao (veiculo_id, horario, local, velocidade, ignicao)
VALUES ('00000000-0000-7000-8000-0000000000a1', now(), 'SRID=4326;POINT(-49.27 -25.43)', 72, true);
INSERT INTO bruto.moovsec_alarme (id_moovsec, horario, placa, tipo, linha_bruta)
VALUES ('M1', now(), 'XXX9X99', 'bocejando', '{}');

-- OPI: percentual calculado respeita item invertido (31) e ignora N.A.
INSERT INTO cadastro.motorista (id, nome, origem) VALUES ('00000000-0000-7000-8000-0000000000b1', 'Motorista Teste', 'manual');
INSERT INTO ia.opi (id, modelo, motorista_id, veiculo_id, mes, tipo, trecho)
VALUES ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5', '00000000-0000-7000-8000-0000000000b1',
        '00000000-0000-7000-8000-0000000000a1', '2026-11-01', 'nao_anunciada', tstzrange('2026-11-10 09:00Z', '2026-11-10 09:15Z'));
INSERT INTO ia.opi_resposta (opi_id, modelo, numero, resposta, origem) VALUES
  ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5',  6, 'nao', 'ia'),   -- sem cinto: não atendido
  ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5',  7, 'sim', 'ia'),   -- atendido
  ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5', 31, 'nao', 'ia'),   -- não apresenta fadiga: atendido
  ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5', 28, 'na',  'ia');   -- não conta
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM ia.fn_opi_resultado('00000000-0000-7000-8000-0000000000c1');
  ASSERT r.avaliados = 3, 'avaliados ' || r.avaliados;
  ASSERT r.atendidos = 2, 'atendidos ' || r.atendidos;
  ASSERT r.percentual = 66.67, 'percentual ' || r.percentual;
  BEGIN
    INSERT INTO ia.opi_resposta (opi_id, modelo, numero, resposta, origem)
    VALUES ('00000000-0000-7000-8000-0000000000c1', 'FFRO005-R5', 36, 'sim', 'ia');
    RAISE EXCEPTION 'deveria recusar o item 36';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END $$;

RESET ROLE;

-- tic_n8n não lê tabela direto
DO $$ BEGIN
  ASSERT NOT has_table_privilege('tic_n8n', 'cadastro.motorista', 'SELECT'), 'tic_n8n não pode ler tabela';
  ASSERT has_table_privilege('tic_leitura', 'cadastro.motorista', 'SELECT'), 'tic_leitura lê';
END $$;

ROLLBACK;
