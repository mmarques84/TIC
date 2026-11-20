-- Papéis do banco TIC. Idempotente: roda em todo deploy.
-- tic_dono:    dono de tabelas e funções; sem login.
-- tic_n8n:     login do n8n; só EXECUTE em sp_* e job_* (permissoes.sql).
-- tic_leitura: login de suporte, só leitura, por túnel SSH.
-- Senhas chegam como variáveis do psql (-v n8n_senha=... -v leitura_senha=...).

SELECT 'CREATE ROLE tic_dono NOLOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tic_dono') \gexec
SELECT 'CREATE ROLE tic_n8n LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tic_n8n') \gexec
SELECT 'CREATE ROLE tic_leitura LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tic_leitura') \gexec

ALTER ROLE tic_n8n PASSWORD :'n8n_senha';
ALTER ROLE tic_leitura PASSWORD :'leitura_senha';
ALTER ROLE tic_n8n SET timezone = 'UTC';

-- O administrador do container pode assumir tic_dono para aplicar migrations.
GRANT tic_dono TO CURRENT_USER;
GRANT CREATE ON DATABASE :"DBNAME" TO tic_dono;

-- Extensões precisam de superusuário: ficam aqui, não nas migrations (que rodam como tic_dono).
CREATE EXTENSION IF NOT EXISTS postgis;     -- distância, raio, áreas
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- impedir períodos sobrepostos (EXCLUDE)
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- bytes aleatórios do UUID v7

-- Ninguém cria nada no schema public.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
