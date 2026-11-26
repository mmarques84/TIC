-- 017 · Intervalo da ingestão da Autotrac: 15 → 30 min. O primeiro ciclo real na VPS (26/11/2026) levou 17 min
-- (186 veículos × 2 chamadas no ritmo que a Autotrac aceita); com 15 min um ciclo começava antes do outro terminar (HTTP 429).
UPDATE controle.parametro SET valor = '30', motivo = 'Ciclo real de 17 min na VPS em 26/11/2026'
WHERE chave IN ('autotrac.telemetria.intervalo_min', 'autotrac.atic.intervalo_min') AND vigencia @> now();
