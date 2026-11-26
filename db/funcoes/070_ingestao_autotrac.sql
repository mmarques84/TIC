-- Ingestão da Autotrac (spec ingestao-autotrac). Recriado a cada deploy.
-- O n8n só busca na API e entrega a lista; placa, mapa, deduplicação e saneamento ficam aqui.

-- ===================== domínio =====================

-- R5: placa a partir do "Name" do veículo na Autotrac. Primeiro trecho no formato de placa (antiga ou Mercosul), sem hífen.
CREATE OR REPLACE FUNCTION cadastro.fn_placa_de_nome(p_nome text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT m[2] || m[3]
  FROM (SELECT regexp_match(upper(coalesce(p_nome, '')), '(^|[^A-Z0-9])([A-Z]{3})-?([0-9][A-Z0-9][0-9]{2})($|[^A-Z0-9])') AS m) x
$$;

-- Ponto a partir de latitude/longitude da fonte; fora da faixa (ou zero/zero) = sem local.
CREATE OR REPLACE FUNCTION bruto.fn_ponto(p_lat numeric, p_lon numeric)
RETURNS geography LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180 AND NOT (p_lat = 0 AND p_lon = 0)
              THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography END
$$;

-- Velocidade aceita pela coluna (0–250); fora disso = sem valor.
CREATE OR REPLACE FUNCTION bruto.fn_velocidade(p_v numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_v BETWEEN 0 AND 250 THEN round(p_v, 1) END
$$;

-- ===================== internos (não expostos ao n8n) =====================

-- Registra (ou soma) um item na fila de saneamento. Item aberto igual não duplica: conta "vezes".
CREATE OR REPLACE FUNCTION controle.int_saneamento(p_fonte text, p_motivo text, p_chave text, p_descricao text, p_dados jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  INSERT INTO controle.saneamento (fonte, motivo, chave, descricao, dados)
  VALUES (p_fonte, p_motivo, left(p_chave, 200), left(p_descricao, 300), coalesce(p_dados, '{}'))
  ON CONFLICT (fonte, motivo, chave) WHERE estado = 'aberto'
  DO UPDATE SET vezes = controle.saneamento.vezes + 1, ultimo_em = now(), dados = EXCLUDED.dados;
END $$;

-- ===================== casos de uso do lote (chamados pelo n8n) =====================

-- R3: resultado de cada chamada à fonte. 401/403 marca senha_mudou e o n8n interrompe o ciclo.
-- p_erro nunca deve trazer credencial; mesmo assim é cortado em 500 caracteres.
CREATE OR REPLACE FUNCTION controle.job_credencial(p_fonte text, p_ok boolean, p_http integer DEFAULT NULL, p_erro text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_bloqueia boolean := NOT p_ok AND p_http IN (401, 403);
BEGIN
  INSERT INTO controle.credencial_status (fonte) VALUES (p_fonte) ON CONFLICT (fonte) DO NOTHING;
  IF p_ok THEN
    UPDATE controle.credencial_status SET ultimo_sucesso = now(), senha_mudou = false, atualizado_em = now() WHERE fonte = p_fonte;
  ELSE
    UPDATE controle.credencial_status
    SET ultimo_erro_em = now(), ultimo_erro = left(coalesce(p_erro, 'erro sem descrição'), 500), ultimo_http = p_http,
        senha_mudou = senha_mudou OR v_bloqueia, atualizado_em = now()
    WHERE fonte = p_fonte;
  END IF;
  RETURN jsonb_build_object('interromper', v_bloqueia);
END $$;

-- R9, R10, R20: abre o lote e devolve o que buscar. Para a frota (autotrac_cadastro) só abre o lote.
-- Para eventos: uma chamada por veículo e janela (no máximo autotrac.janela_max_h cada), desde o último evento
-- recebido menos a sobreposição, nunca antes do que a Autotrac guarda. Retorna também as perdas (R10).
CREATE OR REPLACE FUNCTION bruto.job_lote_abrir(p_fonte text, p_agora timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_lote uuid;
  v_senha boolean;
  v_janela interval := make_interval(hours => controle.fn_parametro_num('autotrac.janela_max_h')::integer);
  v_sobre interval := make_interval(mins => controle.fn_parametro_num('autotrac.telemetria.sobreposicao_min')::integer);
  v_inicio interval := make_interval(hours => controle.fn_parametro_num('autotrac.telemetria.inicio_h')::integer);
  v_limite timestamptz := p_agora - make_interval(days => controle.fn_parametro_num('autotrac.retencao_dias')::integer);
  v_chamadas jsonb := '[]'; v_perdas jsonb := '[]';
  r record; v_de timestamptz; v_ate timestamptz;
BEGIN
  SELECT senha_mudou INTO v_senha FROM controle.credencial_status WHERE fonte = 'autotrac';
  IF coalesce(v_senha, false) THEN
    RETURN jsonb_build_object('lote', NULL, 'bloqueado', true, 'motivo', 'Credencial da Autotrac recusada (401/403): corrigir antes de buscar');
  END IF;

  INSERT INTO bruto.ingestao_lote (fonte, inicio) VALUES (p_fonte, p_agora) RETURNING id INTO v_lote;

  IF p_fonte = 'autotrac_evento' THEN
    FOR r IN
      SELECT v.id, v.id_autotrac, (SELECT max(e.horario) FROM bruto.autotrac_evento e WHERE e.veiculo_id = v.id) AS ultimo
      FROM cadastro.veiculo v
      WHERE v.ativo AND v.id_autotrac IS NOT NULL
      ORDER BY v.placa
    LOOP
      v_de := coalesce(r.ultimo - v_sobre, p_agora - v_inicio);
      IF v_de < v_limite THEN
        v_perdas := v_perdas || jsonb_build_object('veiculo', r.id, 'de', r.ultimo, 'ate', v_limite);
        v_de := v_limite;
      END IF;
      WHILE v_de < p_agora LOOP
        v_ate := least(v_de + v_janela, p_agora);
        v_chamadas := v_chamadas || jsonb_build_object('veiculo', r.id, 'codigo', r.id_autotrac,
          'de', to_char(v_de AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
          'ate', to_char(v_ate AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'));
        v_de := v_ate;
      END LOOP;
    END LOOP;
    UPDATE bruto.ingestao_lote
    SET cursor_ate = to_char(p_agora AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
        erro = CASE WHEN jsonb_array_length(v_perdas) > 0
                    THEN left('Dados perdidos (mais de ' || controle.fn_parametro_num('autotrac.retencao_dias') || ' dias sem buscar) em '
                              || jsonb_array_length(v_perdas) || ' veículo(s)', 1000) END
    WHERE id = v_lote;
    -- Nada para buscar (nenhum veículo ligado): fecha o lote na hora, para não ficar "rodando".
    IF jsonb_array_length(v_chamadas) = 0 THEN
      UPDATE bruto.ingestao_lote SET fim = now(), estado = CASE WHEN erro IS NULL THEN 'ok' ELSE 'erro' END WHERE id = v_lote;
    END IF;
  END IF;

  RETURN jsonb_build_object('lote', v_lote, 'bloqueado', false,
    'url', controle.fn_parametro('autotrac.url_telemetria') #>> '{}',
    'conta', controle.fn_parametro_num('autotrac.conta_telemetria')::bigint,
    'chamadas', v_chamadas, 'perdas', v_perdas);
END $$;

-- R20: fecha o lote. Falha em algum veículo → estado erro com a lista (sem dado sensível).
CREATE OR REPLACE FUNCTION bruto.job_lote_fechar(p_lote uuid, p_falhas jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_falhas jsonb := coalesce(p_falhas, '[]'); v_estado text; v_linhas integer;
BEGIN
  UPDATE bruto.ingestao_lote
  SET fim = now(),
      estado = CASE WHEN jsonb_array_length(v_falhas) > 0 OR erro IS NOT NULL THEN 'erro' ELSE 'ok' END,
      erro = left(concat_ws(' · ', erro,
               CASE WHEN jsonb_array_length(v_falhas) > 0
                    THEN 'Falha em ' || jsonb_array_length(v_falhas) || ' chamada(s): '
                         || (SELECT string_agg(coalesce(f->>'placa', f->>'veiculo', '?') || ' ' || coalesce(f->>'http', ''), ', ')
                             FROM jsonb_array_elements(v_falhas) f) END), 1000)
  WHERE id = p_lote
  RETURNING estado, linhas INTO v_estado, v_linhas;
  IF NOT FOUND THEN RAISE EXCEPTION 'LOTE_INEXISTENTE' USING ERRCODE = 'P0001'; END IF;
  RETURN jsonb_build_object('lote', p_lote, 'estado', v_estado, 'linhas', v_linhas);
END $$;

-- R4–R8: aplica a lista completa de veículos da Autotrac (todas as páginas de uma vez, para achar placa repetida).
-- Liga o código só quando a placa existe, não está repetida, não tem anotação e não há conflito. Nunca cria nem desativa veículo.
CREATE OR REPLACE FUNCTION cadastro.job_autotrac_veiculos(p_lote uuid, p_itens jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  r record; v_veiculo uuid; v_atual text; v_dono uuid;
  v_ligados integer := 0; v_iguais integer := 0; v_saneamento integer := 0;
BEGIN
  FOR r IN
    WITH itens AS (
      SELECT i->>'Code' AS codigo, i->>'Name' AS nome, i->>'Address' AS equipamento,
             cadastro.fn_placa_de_nome(i->>'Name') AS placa,
             (i->>'Name') ~* '(vendido|antiga)' AS anotado
      FROM jsonb_array_elements(coalesce(p_itens, '[]')) i
      WHERE i->>'Code' IS NOT NULL
    )
    SELECT x.*, count(*) FILTER (WHERE NOT x.anotado) OVER (PARTITION BY x.placa) AS repetidas FROM itens x
  LOOP
    IF r.placa IS NULL THEN
      PERFORM controle.int_saneamento('autotrac', 'veiculo_sem_placa', r.codigo,
        'Veículo da Autotrac sem placa no nome: "' || coalesce(r.nome, '') || '" (equipamento ' || coalesce(r.equipamento, '?') || ')',
        jsonb_build_object('codigo', r.codigo, 'nome', r.nome, 'equipamento', r.equipamento));
      v_saneamento := v_saneamento + 1; CONTINUE;
    END IF;
    IF r.anotado THEN
      PERFORM controle.int_saneamento('autotrac', 'veiculo_anotado', r.codigo,
        'Veículo da Autotrac com anotação no nome: "' || r.nome || '" (placa ' || r.placa || '); código não foi ligado',
        jsonb_build_object('codigo', r.codigo, 'nome', r.nome, 'placa', r.placa));
      v_saneamento := v_saneamento + 1; CONTINUE;
    END IF;
    IF r.repetidas > 1 THEN
      PERFORM controle.int_saneamento('autotrac', 'placa_duplicada', r.placa,
        'Placa ' || r.placa || ' aparece em mais de um veículo da Autotrac; nenhum código foi ligado',
        jsonb_build_object('placa', r.placa));
      v_saneamento := v_saneamento + 1; CONTINUE;
    END IF;

    SELECT id, id_autotrac INTO v_veiculo, v_atual FROM cadastro.veiculo WHERE placa = r.placa;
    IF v_veiculo IS NULL THEN
      PERFORM controle.int_saneamento('autotrac', 'placa_sem_cadastro', r.placa,
        'Placa ' || r.placa || ' está na Autotrac e não está no cadastro do painel',
        jsonb_build_object('codigo', r.codigo, 'nome', r.nome, 'placa', r.placa));
      v_saneamento := v_saneamento + 1; CONTINUE;
    END IF;

    IF v_atual = r.codigo THEN v_iguais := v_iguais + 1; CONTINUE; END IF;

    SELECT id INTO v_dono FROM cadastro.veiculo WHERE id_autotrac = r.codigo AND id <> v_veiculo;
    IF v_atual IS NOT NULL OR v_dono IS NOT NULL THEN
      PERFORM controle.int_saneamento('autotrac', 'codigo_em_conflito', r.codigo,
        'Código ' || r.codigo || ' da Autotrac (placa ' || r.placa || ') conflita com o cadastro; nada foi alterado',
        jsonb_build_object('codigo', r.codigo, 'placa', r.placa, 'codigo_atual_da_placa', v_atual));
      v_saneamento := v_saneamento + 1; CONTINUE;
    END IF;

    UPDATE cadastro.veiculo SET id_autotrac = r.codigo, atualizado_em = now() WHERE id = v_veiculo;
    v_ligados := v_ligados + 1;
  END LOOP;

  UPDATE bruto.ingestao_lote SET linhas = linhas + v_ligados WHERE id = p_lote;
  RETURN jsonb_build_object('ligados', v_ligados, 'ja_ligados', v_iguais, 'saneamento', v_saneamento);
END $$;

-- R11–R15: grava os eventos de um veículo. p_tipo: 'telemetria' (alltelemetryevents) ou 'sds' (safetydrivingevents).
-- Idempotente pela chave (veículo, horário, tipo). Nunca guarda CPF.
CREATE OR REPLACE FUNCTION bruto.job_autotrac_eventos(p_lote uuid, p_veiculo uuid, p_tipo text, p_itens jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  i jsonb; v_fonte text; v_chave text; v_tipo text; v_horario timestamptz; v_dados jsonb;
  v_mot text; v_mot_id uuid; v_n integer; v_gravados integer := 0; v_repetidos integer := 0; v_desconhecidos integer := 0;
  v_fora integer := 0;
BEGIN
  IF p_tipo NOT IN ('telemetria', 'sds') THEN RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  IF NOT EXISTS (SELECT 1 FROM cadastro.veiculo WHERE id = p_veiculo) THEN RAISE EXCEPTION 'VEICULO_INEXISTENTE' USING ERRCODE = 'P0001'; END IF;
  v_fonte := 'autotrac_' || p_tipo;

  FOR i IN SELECT * FROM jsonb_array_elements(coalesce(p_itens, '[]')) LOOP
    -- R13: o original sem CPF (em qualquer grafia de chave).
    v_dados := (SELECT coalesce(jsonb_object_agg(k, v), '{}') FROM jsonb_each(i) AS e(k, v) WHERE k !~* 'cpf');
    IF p_tipo = 'telemetria' THEN
      v_chave := i->>'EventNumberStart';
      v_horario := (i->>'EventDateTimeStart')::timestamptz;
      v_mot := nullif(nullif(i->>'DriverID', ''), '0');
    ELSE
      v_chave := btrim(i->>'EventName');
      v_horario := (i->>'EventTime')::timestamptz;
      v_mot := NULL;
    END IF;
    CONTINUE WHEN v_horario IS NULL OR v_chave IS NULL;
    -- R10: fora do que a Autotrac guarda (ou no futuro) não entra: evita partição inexistente e dado incoerente.
    IF v_horario < now() - make_interval(days => controle.fn_parametro_num('autotrac.retencao_dias')::integer + 1)
       OR v_horario > now() + interval '1 day' THEN
      v_fora := v_fora + 1; CONTINUE;
    END IF;

    SELECT tipo INTO v_tipo FROM controle.evento_mapa WHERE fonte = v_fonte AND chave = v_chave;
    IF v_tipo IS NULL THEN
      v_tipo := 'desconhecido';
      v_desconhecidos := v_desconhecidos + 1;
      PERFORM controle.int_saneamento('autotrac', 'tipo_evento_sem_mapa', v_fonte || ':' || v_chave,
        'Evento ' || CASE p_tipo WHEN 'sds' THEN 'de câmera "' ELSE 'de telemetria nº "' END || v_chave || '" sem tipo no mapa',
        jsonb_build_object('fonte', v_fonte, 'chave', v_chave));
    END IF;

    v_mot_id := NULL;
    IF v_mot IS NOT NULL THEN
      SELECT id INTO v_mot_id FROM cadastro.motorista WHERE codigo_autotrac = v_mot;
      IF v_mot_id IS NULL THEN
        PERFORM controle.int_saneamento('autotrac', 'motorista_sem_cadastro', v_mot,
          'Motorista com código ' || v_mot || ' na Autotrac não está no cadastro do painel',
          jsonb_build_object('codigo', v_mot, 'nome', i->>'DriverName'));
      END IF;
    END IF;

    INSERT INTO bruto.autotrac_evento (veiculo_id, horario, tipo, valor, local, velocidade, dados, lote_id,
                                       motorista_id, codigo_motorista, origem_id)
    VALUES (p_veiculo, v_horario, v_tipo,
            CASE WHEN p_tipo = 'telemetria' THEN nullif(i->>'VelocityMax', '')::numeric END,
            CASE WHEN p_tipo = 'telemetria'
                 THEN bruto.fn_ponto(nullif(i->>'StartLatitude', '')::numeric, nullif(i->>'StartLongitude', '')::numeric)
                 ELSE bruto.fn_ponto(nullif(i->>'Latitude', '')::numeric, nullif(i->>'Longitude', '')::numeric) END,
            bruto.fn_velocidade(CASE WHEN p_tipo = 'telemetria'
                                     THEN coalesce(nullif(i->>'VelocityMax', ''), nullif(i->>'VelocityStart', ''))::numeric
                                     ELSE nullif(i->>'Velocity', '')::numeric END),
            v_dados || jsonb_build_object('fonte', v_fonte, 'chave', v_chave), p_lote,
            v_mot_id, v_mot, coalesce(i->>'Code', i->>'ID'))
    ON CONFLICT (veiculo_id, horario, tipo) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 1 THEN v_gravados := v_gravados + 1; ELSE v_repetidos := v_repetidos + 1; END IF;
  END LOOP;

  UPDATE bruto.ingestao_lote SET linhas = linhas + v_gravados WHERE id = p_lote;
  RETURN jsonb_build_object('gravados', v_gravados, 'repetidos', v_repetidos, 'desconhecidos', v_desconhecidos, 'fora_do_periodo', v_fora);
END $$;
