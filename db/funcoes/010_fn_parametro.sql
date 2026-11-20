-- Domínio: leitura de parâmetro vigente (o da operação vence o global). Recriada a cada deploy.

CREATE OR REPLACE FUNCTION controle.fn_parametro(p_chave text, p_operacao_id uuid DEFAULT NULL, p_em timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT valor
  FROM controle.parametro
  WHERE chave = p_chave
    AND vigencia @> p_em
    AND (operacao_id = p_operacao_id OR operacao_id IS NULL)
  ORDER BY operacao_id IS NULL   -- false (da operação) vem antes de true (global)
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION controle.fn_parametro_num(p_chave text, p_operacao_id uuid DEFAULT NULL, p_em timestamptz DEFAULT now())
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v jsonb := controle.fn_parametro(p_chave, p_operacao_id, p_em);
BEGIN
  IF v IS NULL OR jsonb_typeof(v) <> 'number' THEN
    RAISE EXCEPTION 'PARAMETRO_AUSENTE' USING ERRCODE = 'P0001', DETAIL = p_chave;
  END IF;
  RETURN v::numeric;
END $$;

-- Domínio: nível de excesso de velocidade a partir das faixas do parâmetro.
CREATE OR REPLACE FUNCTION controle.fn_nivel_velocidade(p_velocidade numeric, p_molhada boolean, p_operacao_id uuid DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE f jsonb := controle.fn_parametro(CASE WHEN p_molhada THEN 'velocidade.molhada' ELSE 'velocidade.seca' END, p_operacao_id);
BEGIN
  IF f IS NULL THEN RAISE EXCEPTION 'PARAMETRO_AUSENTE' USING ERRCODE = 'P0001'; END IF;
  IF p_velocidade > (f->>'grave_acima')::numeric THEN RETURN 'grave'; END IF;
  IF p_velocidade >= (f->'medio'->>0)::numeric THEN RETURN 'medio'; END IF;
  IF p_velocidade >= (f->'leve'->>0)::numeric THEN RETURN 'leve'; END IF;
  RETURN NULL;
END $$;

-- Domínio: percentual da OPI calculado pelas respostas (respeita itens invertidos e N.A.).
CREATE OR REPLACE FUNCTION ia.fn_opi_resultado(p_opi_id uuid)
RETURNS TABLE (avaliados integer, atendidos integer, percentual numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT count(*)::integer,
         count(*) FILTER (WHERE (r.resposta = 'sim') <> i.invertido)::integer,
         round(100.0 * count(*) FILTER (WHERE (r.resposta = 'sim') <> i.invertido) / nullif(count(*), 0), 2)
  FROM ia.opi_resposta r
  JOIN ia.opi_modelo_item i ON i.modelo = r.modelo AND i.numero = r.numero
  WHERE r.opi_id = p_opi_id AND r.resposta <> 'na'
$$;
