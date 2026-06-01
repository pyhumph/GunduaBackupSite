#!/bin/bash
# Wait for MariaDB (started by supervisord) to accept TCP on 5054, then start WP.
set -e

echo "[aio] Waiting for MariaDB on 127.0.0.1:5054..."
for i in $(seq 60 -1 0); do
  if mariadb-admin --host=127.0.0.1 --port=5054 --protocol=tcp \
       -u"${DB_USER}" -p"${DB_PASSWORD}" ping &>/dev/null; then
    echo "[aio] MariaDB is up."
    break
  fi
  if [ "$i" = 0 ]; then echo "[aio] MariaDB not reachable on 5054 — continuing anyway"; fi
  sleep 1
done

exec docker-entrypoint.sh apache2-foreground
