# Gundua Africa — Emergency WordPress Restore on Docker (server1)

Temporary failover while the cPanel host is out of resources. Restore the MAIN
site **gunduaafrica.com**, serve it via your existing **Nginx Proxy Manager**,
hand back to the shared host once the admin raises PMEM/EP limits.

> `gunduaafricasafaris.com` is only a 301 redirect to gunduaafrica.com — you do
> NOT restore it. Recreate that redirect in NPM later (Phase 4, optional).

> Architecture: ONE all-in-one container runs both WordPress and MariaDB,
> managed by supervisord. WordPress talks to the DB over `127.0.0.1:5054`
> INSIDE the container — no Docker DNS, no inter-container networking, fully
> immune to your server's host-DNS issue. MariaDB uses **5054**, never 3306,
> so it can't collide with Webuzo. NPM proxies the domain to host port 5053.

---

## Phase 0 — Folder layout (on server1)

```
~/production/applications/gundua/
├── docker-compose.yml
├── Dockerfile
├── .env                      # from .env.example, filled in
├── docker/
│   ├── entrypoint.sh
│   ├── start-apache.sh
│   ├── supervisord.conf
│   └── mariadb-port.cnf
└── backup/
    ├── database.sql          # phpMyAdmin export of the site DB
    └── wp-content/           # themes, plugins, uploads from the old site
```

Copy the whole project folder to `~/production/applications/gundua/`, then:
```bash
mkdir -p ~/production/applications/gundua/backup
```

---

## Phase 1 — Get the backup OUT (despite the fork limit)

Both tools below run under the web server, so they avoid `Unable to fork`.

### 1a. First, read the 3 values you need from wp-config.php
cPanel ▸ **File Manager** ▸ `public_html/wp-config.php` ▸ **View**. Note:
- `DB_NAME`        → which database to export in phpMyAdmin
- `$table_prefix`  → goes in `.env` as `TABLE_PREFIX` (often NOT plain `wp_`)
- `DB_NAME`/`DB_USER` are the OLD creds — you do NOT reuse them; the container
  gets fresh creds from `.env`.

### 1b. Database → phpMyAdmin
1. cPanel ▸ **phpMyAdmin** ▸ select the `DB_NAME` database.
2. **Export** ▸ Custom ▸ Format **SQL**.
   - Tick **Add DROP TABLE / VIEW** (clean re-import).
   - If large, set Compression **gzip**.
3. Download → save as `backup/database.sql` (gunzip first if it's `.sql.gz`).

> If phpMyAdmin times out under limits: export a few tables at a time, or ask
> the admin for a one-off `mysqldump` (a 2-second job on their side).

### 1c. Files → File Manager (zip + download)
You only need **wp-content**.
1. File Manager ▸ enter `public_html/` ▸ select the **wp-content** folder.
2. **Compress** ▸ Zip ▸ download the zip ▸ extract into `backup/wp-content/`.

> Compressing is itself a process and may hit the fork limit on a big `uploads`
> folder. If the zip fails: compress in chunks — go into
> `wp-content/uploads/` and zip each **year** folder (2023, 2024, 2025…)
> separately, plus zip `themes/` and `plugins/` on their own. Reassemble under
> `backup/wp-content/` on the server preserving the same paths.

End state on server1:
```
backup/wp-content/themes/...
backup/wp-content/plugins/...
backup/wp-content/uploads/...
```

---

## Phase 2 — Configure

```bash
cd ~/production/applications/gundua
cp .env.example .env
nano .env
```
Set: DB passwords (you invent these), `TABLE_PREFIX` (from wp-config.php),
and for now `SITE_URL=http://<server1-ip>:5053`.

---

## Phase 3 — Build + launch + preview

This image is BUILT locally (WordPress + MariaDB + supervisor):
```bash
docker compose build
docker compose up -d
docker compose logs -f gundua         # watch [aio] init + import; Ctrl-C to stop
```

> **Build needs working DNS** (apt-get inside the build resolves Debian repos).
> If your host-DNS issue makes the build fail to resolve, set the Docker daemon's
> DNS once and rebuild:
> ```bash
> echo '{ "dns": ["8.8.8.8", "1.1.1.1"] }' | sudo tee /etc/docker/daemon.json
> sudo systemctl restart docker
> docker compose build
> ```

The DB auto-imports `backup/database.sql` on first boot (only while the `db_data`
volume is empty — to re-import, `docker compose down -v` first). MySQL is
reachable from the host at `127.0.0.1:5054` if you need a client.
Preview at **http://<server1-ip>:5053**.

Redirects bouncing you to the old domain? The DB still holds the old `siteurl`.
The `WP_HOME/WP_SITEURL` defines in compose mask it for preview. Make it
permanent AFTER cutover with:
```bash
docker compose exec gundua bash -c '
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar;
  php wp-cli.phar --allow-root search-replace "https://gunduaafrica.com" "$WP_HOME"'
```
(needs the container to reach the internet once; if your host-DNS issue blocks
that, add `dns: ["8.8.8.8", "1.1.1.1"]` under the `gundua` service in compose
and `docker compose up -d` again.)

---

## Phase 4 — Serve the domain via Nginx Proxy Manager

1. In **NPM** ▸ **Proxy Hosts** ▸ Add Proxy Host:
   - Domain Names: `gunduaafrica.com`, `www.gunduaafrica.com`
   - Scheme: `http`
   - **Forward Hostname/IP**: `<server1-LAN-IP>`  (NOT `localhost` — inside the
     NPM container localhost is the container itself. Use the host IP, or attach
     NPM to the same docker network and forward to `gundua_wp` on port `80`.)
   - **Forward Port**: `5053`  (or `80` if forwarding to `gundua_wp` by name)
   - Block Common Exploits: on. Websockets: on.
   - **SSL** tab: request a new **Let's Encrypt** cert, Force SSL + HTTP/2.
2. Flip `.env` → `SITE_URL=https://gunduaafrica.com`, then `docker compose up -d`.
3. Run the Phase 3 `search-replace` so the DB matches the live URL.
4. Recreate the safaris redirect: NPM ▸ **Redirection Hosts** ▸ Add ▸
   `gunduaafricasafaris.com` (+www) ▸ Forward to `https://gunduaafrica.com`,
   HTTP Code **301**, Preserve Path on, request Let's Encrypt SSL.

### DNS cutover (registrar panel)
1. A few hours ahead: lower the domain's **TTL** to 300s.
2. Point the **A record** for `gunduaafrica.com` (and `www`) to server1's public IP.
3. Make sure the server firewall allows 80/443 (NPM needs 80 for cert issuance).

---

## Phase 5 — Hand back to the shared host (later)
Once the admin restarts processes / raises PMEM & EP (entry process) limits:
1. Re-point the A record back to the cPanel server IP, lower TTL first.
2. Export the container DB (`docker compose exec database mariadb-dump ...`) and
   re-import any content created during the outage; copy any new uploads back.
3. After DNS fully propagates: `docker compose down` (keep the `db_data` volume
   until you've confirmed the host site is fully current).
```bash
# export the live container DB before tearing down
docker compose exec gundua sh -c \
  'exec mariadb-dump --host=127.0.0.1 --port=5054 -uroot -p"$DB_ROOT_PASSWORD" "$DB_NAME"' \
  > handover.sql
```
