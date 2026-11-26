-- 016 · Lista de unidades autorizadas da Autotrac (spec ingestao-autotrac R9b).
-- Só os veículos dessa lista devolvem dados (fora dela: HTTP 422 "O equipamento não está na lista de unidades
-- autorizadas", visto na VPS em 26/11/2026), e a Autotrac cobra por veículo na lista. O ciclo de eventos só busca os autorizados.
-- NULL = ainda não conferido (busca); false = fora da lista (não busca).
ALTER TABLE cadastro.veiculo
  ADD COLUMN autorizado_telemetria boolean NULL,
  ADD COLUMN autorizado_atic       boolean NULL;
