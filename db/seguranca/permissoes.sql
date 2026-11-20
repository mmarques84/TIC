-- Permissões. Idempotente: roda em todo deploy, depois das migrations e funções.
-- tic_n8n não lê nem escreve tabela: só chama sp_* (casos de uso) e job_* (lotes).
-- As funções são SECURITY DEFINER (rodam como tic_dono), então fazem o trabalho por ele.

DO $$
DECLARE s text; f record;
BEGIN
  FOREACH s IN ARRAY ARRAY['acesso','cadastro','bruto','derivado','ia','controle'] LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO tic_n8n, tic_leitura', s);
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM tic_n8n', s);
    EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA %I FROM PUBLIC', s);
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO tic_leitura', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE tic_dono IN SCHEMA %I REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE tic_dono IN SCHEMA %I GRANT SELECT ON TABLES TO tic_leitura', s);
  END LOOP;

  FOR f IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('acesso','cadastro','bruto','derivado','ia','controle')
      AND (p.proname LIKE 'sp\_%' OR p.proname LIKE 'job\_%')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO tic_n8n', f.nspname, f.proname, f.args);
  END LOOP;
END $$;

-- Funções de apoio usadas em DEFAULT de coluna precisam ser executáveis por quem insere (as sp_* rodam como tic_dono).
GRANT EXECUTE ON FUNCTION controle.uuid_v7() TO tic_dono;
