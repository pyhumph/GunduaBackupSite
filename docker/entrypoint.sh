#!/bin/bash
# First-boot DB init (create DB+user, import backup), then hand off to supervisord.
set -euo pipefail

DATADIR=/var/lib/mysql
SOCKET=/run/mysqld/mysqld.sock

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld "$DATADIR"

if [ ! -d "$DATADIR/mysql" ]; then
  echo "[aio] Initializing MariaDB data directory..."
  mariadb-install-db --user=mysql --datadir="$DATADIR" \
      --auth-root-authentication-method=normal --skip-test-db >/dev/null

  echo "[aio] Bootstrapping DB / user / import (temporary local server)..."
  mariadbd --user=mysql --datadir="$DATADIR" --socket="$SOCKET" --skip-networking &
  pid="$!"

  for i in $(seq 60 -1 0); do
    if mariadb-admin --socket="$SOCKET" ping &>/dev/null; then break; fi
    if [ "$i" = 0 ]; then echo "[aio] MariaDB failed to start"; exit 1; fi
    sleep 1
  done

  mariadb --socket="$SOCKET" <<-EOSQL
    SET @@SESSION.SQL_LOG_BIN=0;
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
    CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
    CREATE USER IF NOT EXISTS '${DB_USER}'@'%'         IDENTIFIED BY '${DB_PASSWORD}';
    CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
    GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
    FLUSH PRIVILEGES;
EOSQL

  if [ -f /backup/database.sql ]; then
    echo "[aio] Importing /backup/database.sql ..."
    mariadb --socket="$SOCKET" "${DB_NAME}" < /backup/database.sql
    echo "[aio] Import complete."
  else
    echo "[aio] No /backup/database.sql found — WordPress will run the fresh install wizard."
  fi

  mariadb-admin --socket="$SOCKET" -uroot -p"${DB_ROOT_PASSWORD}" shutdown
  wait "$pid" 2>/dev/null || true
  echo "[aio] DB initialization done."
else
  echo "[aio] Existing MariaDB data dir found — skipping init."
fi

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/aio.conf
