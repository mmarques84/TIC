#!/bin/sh
# Backup diário do banco (pg_dump -Fc) na VPS. Chamado pelo cron do usuário tic às 03:15 UTC:
#   15 3 * * * sh /opt/tic/scripts/backup.sh >> /opt/tic-backups/backup.log 2>&1
# Guarda 14 dias em /opt/tic-backups (chmod 700). Também antes de toda migration em produção (regra 1 do projeto).
# PENDENTE: cópia para fora da VPS (destino a definir com a TIC) e um teste de restauração antes de entrar dado real.
set -eu
cd "$(dirname "$0")/.."
destino=/opt/tic-backups
mkdir -p "$destino"; chmod 700 "$destino"
arq="$destino/tic-$(date -u +%Y%m%d-%H%M).dump"
docker compose exec -T postgres pg_dump -U tic_admin -d tic -Fc > "$arq.parcial"
mv "$arq.parcial" "$arq"; chmod 600 "$arq"
find "$destino" -name 'tic-*.dump' -mtime +14 -delete
echo "$(date -u +%FT%TZ) ok $(basename "$arq") $(du -h "$arq" | cut -f1)"
