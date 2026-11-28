-- Condução, segunda entrega (spec relatorio-conducao R5–R13; layout aprovado em 28/11/2026, artboard 10).
-- Ranking por motorista ou por caminhão, detalhe da linha e exportação. Só lê o banco (R14). Recriado a cada deploy.
-- A consulta de eventos da primeira entrega (100_conducao.sql) continua como a lista "Eventos".

DROP FUNCTION IF EXISTS derivado.sp_conducao_ranking(uuid, text, text, text, text);
DROP FUNCTION IF EXISTS derivado.sp_conducao_detalhe(uuid, text, text, text);
DROP FUNCTION IF EXISTS derivado.sp_conducao_exportar(uuid, text, text, text, text, inet);

-- Eventos do período no escopo da pessoa, com a chave do motorista (cadastro ou código da Autotrac),
-- duração em minutos (quando há fim) e km do evento temporizado (hodômetro; base do "por 100 km", R7).
CREATE OR REPLACE FUNCTION derivado.int_conducao_base(p_usuario uuid, p_periodo text)
RETURNS TABLE (horario timestamptz, tipo text, veiculo_id uuid, placa text, operacao text,
               chave_motorista text, nome_motorista text, cadastrado boolean, codigo_autotrac text,
               minutos numeric, km numeric, velocidade numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_inicio date; v_fim date;
BEGIN
  SELECT p.inicio, p.fim INTO v_inicio, v_fim FROM derivado.fn_periodo_conducao(p_periodo) p;
  RETURN QUERY
  SELECT e.horario, e.tipo, e.veiculo_id, v.placa, o.nome,
         coalesce(m.id::text, 'autotrac:' || nullif(nullif(btrim(e.codigo_motorista), ''), '0')),
         coalesce(m.nome, nullif(btrim(e.dados->>'DriverName'), '')),
         m.id IS NOT NULL,
         nullif(nullif(btrim(e.codigo_motorista), ''), '0'),
         CASE WHEN e.tipo IN ('fora_faixa_verde', 'marcha_lenta_excessiva') AND nullif(e.dados->>'EventDateTimeEnd', '') IS NOT NULL
              THEN greatest(0, least(600, extract(epoch FROM ((e.dados->>'EventDateTimeEnd')::timestamptz - e.horario)) / 60)) END,
         CASE WHEN e.tipo = 'temporizado'
              THEN greatest(0, least(500, nullif(e.dados->>'HodometerEnd', '')::numeric - nullif(e.dados->>'HodometerStart', '')::numeric)) END,
         e.velocidade
  FROM bruto.autotrac_evento e
  JOIN cadastro.veiculo v ON v.id = e.veiculo_id
  LEFT JOIN cadastro.operacao o ON o.id = v.operacao_id
  LEFT JOIN cadastro.motorista atual ON e.motorista_id IS NULL AND atual.codigo_autotrac = nullif(nullif(btrim(e.codigo_motorista), ''), '0')
  LEFT JOIN cadastro.motorista m ON m.id = coalesce(e.motorista_id, atual.id)
  WHERE e.horario >= v_inicio::timestamp AT TIME ZONE 'America/Sao_Paulo'
    AND e.horario < v_fim::timestamp AT TIME ZONE 'America/Sao_Paulo'
    AND (e.tipo = 'temporizado' OR e.tipo = ANY (derivado.fn_tipos_conducao()))
    AND acesso.fn_ve_operacao(p_usuario, v.operacao_id);
END $$;

-- Monta o ranking (R5–R11) a partir da base. p_visao 'motorista' | 'caminhao'; p_tipo '' ou um tipo de condução; p_q busca.
CREATE OR REPLACE FUNCTION derivado.int_conducao_ranking(p_usuario uuid, p_periodo text, p_visao text, p_tipo text, p_q text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_motorista boolean := coalesce(nullif(p_visao, ''), 'motorista') = 'motorista';
  v_q text := lower(btrim(coalesce(p_q, '')));
  v_km_min numeric := 50;  -- abaixo disso a taxa por 100 km não é confiável (R7: "—")
  v_linhas jsonb; v_resumo jsonb;
BEGIN
  IF coalesce(nullif(p_visao, ''), 'motorista') NOT IN ('motorista', 'caminhao')
     OR (coalesce(p_tipo, '') <> '' AND NOT (p_tipo = ANY (derivado.fn_tipos_conducao()))) THEN
    RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
  END IF;

  WITH base AS (SELECT * FROM derivado.int_conducao_base(p_usuario, p_periodo)),
  -- R9: no ranking do motorista, pressão do óleo não entra (é do caminhão)
  evt AS (
    SELECT * FROM base
    WHERE tipo <> 'temporizado'
      AND (v_motorista IS FALSE OR tipo NOT IN ('pressao_oleo_baixa', 'pressao_oleo_alta'))
      AND (coalesce(p_tipo, '') = '' OR tipo = p_tipo)
  ),
  grupo AS (
    SELECT CASE WHEN v_motorista THEN coalesce(b.chave_motorista, 'sem_motorista') ELSE b.veiculo_id::text END AS chave, b.*
    FROM base b
  ),
  agg AS (
    SELECT g.chave,
      max(CASE WHEN v_motorista THEN coalesce(g.nome_motorista, 'Não identificado') ELSE g.placa END) AS nome,
      bool_or(g.cadastrado) AS cadastrado, max(g.codigo_autotrac) AS codigo, max(g.operacao) AS operacao,
      CASE WHEN v_motorista THEN count(DISTINCT g.veiculo_id) ELSE count(DISTINCT g.chave_motorista) END AS outros,
      coalesce(sum(g.km), 0) AS km
    FROM grupo g GROUP BY g.chave
  ),
  cont AS (
    SELECT CASE WHEN v_motorista THEN coalesce(e.chave_motorista, 'sem_motorista') ELSE e.veiculo_id::text END AS chave,
      count(*) AS total,
      count(*) FILTER (WHERE e.tipo IN ('velocidade_excessiva', 'velocidade_excessiva_chuva')) AS vel,
      count(*) FILTER (WHERE e.tipo = 'rpm_excessiva') AS rpm,
      count(*) FILTER (WHERE e.tipo = 'fora_faixa_verde') AS faixa,
      round(coalesce(sum(e.minutos) FILTER (WHERE e.tipo = 'fora_faixa_verde'), 0)) AS faixa_min,
      count(*) FILTER (WHERE e.tipo = 'marcha_lenta_excessiva') AS lenta,
      round(coalesce(sum(e.minutos) FILTER (WHERE e.tipo = 'marcha_lenta_excessiva'), 0)) AS lenta_min,
      count(*) FILTER (WHERE e.tipo = 'banguela') AS banguela,
      count(*) FILTER (WHERE e.tipo IN ('aceleracao_brusca', 'freada_brusca')) AS bruscas,
      count(*) FILTER (WHERE e.tipo IN ('pressao_oleo_baixa', 'pressao_oleo_alta')) AS oleo
    FROM evt e GROUP BY 1
  ),
  tot AS (SELECT coalesce(sum(c.total), 0) AS eventos, (SELECT coalesce(sum(a.km), 0) FROM agg a) AS km FROM cont c),
  lin AS (
    SELECT a.*, coalesce(c.total, 0) AS total, coalesce(c.vel, 0) AS vel, coalesce(c.rpm, 0) AS rpm,
      coalesce(c.faixa, 0) AS faixa, coalesce(c.faixa_min, 0) AS faixa_min, coalesce(c.lenta, 0) AS lenta,
      coalesce(c.lenta_min, 0) AS lenta_min, coalesce(c.banguela, 0) AS banguela, coalesce(c.bruscas, 0) AS bruscas,
      coalesce(c.oleo, 0) AS oleo,
      CASE WHEN a.km >= v_km_min THEN round(100.0 * coalesce(c.total, 0) / a.km, 2) END AS taxa
    FROM agg a LEFT JOIN cont c ON c.chave = a.chave
    WHERE coalesce(c.total, 0) > 0 OR a.km > 0
  ),
  media AS (SELECT CASE WHEN t.km >= v_km_min THEN round(100.0 * t.eventos / t.km, 2) END AS valor FROM tot t)
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'chave', l.chave, 'nome', l.nome,
      'sub', CASE WHEN NOT v_motorista THEN coalesce(l.operacao, 'sem operação')
                  WHEN l.chave = 'sem_motorista' THEN 'eventos sem motorista logado'
                  WHEN l.cadastrado THEN coalesce(l.operacao, 'sem operação')
                  ELSE 'cód. Autotrac ' || coalesce(l.codigo, '?') || ' · não cadastrado' END,
      'cadastrado', coalesce(l.cadastrado, false),
      'outros', l.outros, 'km', round(l.km), 'total', l.total, 'taxa', l.taxa,
      'vezes', CASE WHEN l.taxa IS NOT NULL AND m.valor > 0 THEN round(l.taxa / m.valor, 1) END,
      'velocidade', l.vel, 'rpm', l.rpm, 'faixa', l.faixa, 'faixaMin', l.faixa_min,
      'lenta', l.lenta, 'lentaMin', l.lenta_min, 'banguela', l.banguela, 'bruscas', l.bruscas, 'oleo', l.oleo)
      ORDER BY l.taxa DESC NULLS LAST, l.total DESC, l.nome), '[]'::jsonb),
    jsonb_build_object('eventos', (SELECT eventos FROM tot), 'km', (SELECT round(km) FROM tot), 'media', m.valor,
      'acimaDe2x', count(*) FILTER (WHERE l.taxa IS NOT NULL AND m.valor > 0 AND l.taxa >= 2 * m.valor))
  INTO v_linhas, v_resumo
  FROM lin l CROSS JOIN media m
  WHERE v_q = '' OR lower(l.nome) LIKE '%' || v_q || '%' OR lower(coalesce(l.codigo, '')) LIKE '%' || v_q || '%'
  GROUP BY m.valor;

  RETURN jsonb_build_object(
    'visao', CASE WHEN v_motorista THEN 'motorista' ELSE 'caminhao' END,
    'linhas', coalesce(v_linhas, '[]'::jsonb),
    'resumo', coalesce(v_resumo, jsonb_build_object('eventos', 0, 'km', 0, 'media', NULL, 'acimaDe2x', 0)),
    'dadosAte', (SELECT max(e.horario) FROM bruto.autotrac_evento e WHERE e.horario > now() - interval '8 days'),
    'estado', controle.fn_estado_integracao('autotrac'));
END $$;

-- R5–R11: ranking para a tela.
CREATE FUNCTION derivado.sp_conducao_ranking(p_usuario uuid, p_periodo text, p_visao text, p_tipo text, p_q text)
RETURNS TABLE (ranking jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'conducao.ver');
  RETURN QUERY SELECT derivado.int_conducao_ranking(p_usuario, p_periodo, p_visao, p_tipo, left(coalesce(p_q, ''), 60));
END $$;

-- R12: linha aberta. Eventos por dia, os caminhões (ou motoristas) e os últimos 10 eventos.
CREATE FUNCTION derivado.sp_conducao_detalhe(p_usuario uuid, p_periodo text, p_visao text, p_chave text)
RETURNS TABLE (detalhe jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_motorista boolean := coalesce(nullif(p_visao, ''), 'motorista') = 'motorista';
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'conducao.ver');
  IF coalesce(p_chave, '') = '' THEN RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  RETURN QUERY
  WITH evt AS (
    SELECT b.* FROM derivado.int_conducao_base(p_usuario, p_periodo) b
    WHERE b.tipo <> 'temporizado'
      AND (CASE WHEN v_motorista THEN coalesce(b.chave_motorista, 'sem_motorista') ELSE b.veiculo_id::text END) = p_chave
      AND (v_motorista IS FALSE OR b.tipo NOT IN ('pressao_oleo_baixa', 'pressao_oleo_alta'))
  )
  SELECT jsonb_build_object(
    'dias', coalesce((SELECT jsonb_agg(jsonb_build_object('dia', to_char(d, 'DD/MM'), 'eventos', n) ORDER BY d)
                      FROM (SELECT (horario AT TIME ZONE 'America/Sao_Paulo')::date AS d, count(*) AS n FROM evt GROUP BY 1) x), '[]'::jsonb),
    'outros', coalesce((SELECT jsonb_agg(o ORDER BY o) FROM (SELECT DISTINCT CASE WHEN v_motorista THEN placa ELSE coalesce(nome_motorista, 'Não identificado') END AS o FROM evt) y), '[]'::jsonb),
    'ultimos', coalesce((SELECT jsonb_agg(jsonb_build_object('horario', horario, 'tipo', tipo, 'placa', placa,
                         'motorista', coalesce(nome_motorista, 'Não identificado'), 'minutos', round(minutos)) ORDER BY horario DESC)
                       FROM (SELECT * FROM evt ORDER BY horario DESC LIMIT 10) z), '[]'::jsonb));
END $$;

-- R13: exportação. Mesmo ranking da tela; grava a auditoria com quem e o filtro (o CSV é montado no navegador).
CREATE FUNCTION derivado.sp_conducao_exportar(p_usuario uuid, p_periodo text, p_visao text, p_tipo text, p_q text, p_ip inet)
RETURNS TABLE (ranking jsonb)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r jsonb;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'conducao.ver');
  r := derivado.int_conducao_ranking(p_usuario, p_periodo, p_visao, p_tipo, left(coalesce(p_q, ''), 60));
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois, ip)
  VALUES (p_usuario, 'conducao.exportar', 'derivado.conducao', NULL, NULL,
          jsonb_build_object('periodo', p_periodo, 'visao', p_visao, 'tipo', p_tipo, 'q', p_q, 'linhas', jsonb_array_length(r->'linhas')), p_ip);
  RETURN QUERY SELECT r;
END $$;
