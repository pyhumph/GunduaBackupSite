#!/bin/bash
# Wait for MariaDB (started by supervisord) to accept TCP on 5054, then start WP.
set -e

echo "[aio] Waiting for MariaDB to accept TCP on 127.0.0.1:5054..."
for i in $(seq 60 -1 0); do
  # Plain TCP check — no auth needed, so it works regardless of user setup.
  if (exec 3<>/dev/tcp/127.0.0.1/5054) 2>/dev/null; then
    exec 3>&- 3<&-
    echo "[aio] MariaDB port is open."
    break
  fi
  if [ "$i" = 0 ]; then echo "[aio] MariaDB not reachable on 5054 — continuing anyway"; fi
  sleep 1
done

exec docker-entrypoint.sh apache2-foreground
