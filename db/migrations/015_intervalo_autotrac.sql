-- 015 · Intervalo da ingestão da Autotrac: 5 → 15 min. A Autotrac limita as chamadas (HTTP 429 na VPS em 26/11/2026);
-- com ~190 veículos × 2 chamadas, uma a cada 1,5 s, o ciclo leva ~10 min. O workflow do n8n agenda no mesmo valor.
UPDATE controle.parametro SET valor = '15', motivo = 'Limite de chamadas da Autotrac (429) em 26/11/2026'
WHERE chave IN ('autotrac.telemetria.intervalo_min', 'autotrac.atic.intervalo_min') AND vigencia @> now();
