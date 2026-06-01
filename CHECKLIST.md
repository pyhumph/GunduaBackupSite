# Your step-by-step checklist (in order)

Tick each box as you go. Tools you'll use: cPanel (File Manager + phpMyAdmin),
your server1 terminal, and Nginx Proxy Manager (NPM). Details/explanations live
in RUNBOOK.md — this is the do-this-then-that list.

## A. On the OLD host (cPanel) — collect the backup
- [ ] 1. (DONE) From `wp-config.php`: DB name `gundua_ius_0opdb`,
        **`$table_prefix = _ifsldf_`** (already pre-filled in `.env.example`).
- [ ] 2. cPanel ▸ **phpMyAdmin** ▸ click the **`gundua_ius_0opdb`** database (left list).
- [ ] 3. **Export** tab ▸ **Custom** ▸ Format **SQL** ▸ tick **Add DROP TABLE / VIEW**
        ▸ **do NOT tick "Add CREATE DATABASE / USE"** ▸ (large DB? Compression = **gzip**)
        ▸ **Export**. Save the file.
- [ ] 4. If you got a `.sql.gz`, unzip it to get **`database.sql`**.
- [ ] 5. Back in **File Manager** ▸ `public_html/` ▸ select the **wp-content** folder
        ▸ **Compress** ▸ Zip ▸ **Download** the zip.
        (If it fails on a big `uploads/`: zip `uploads/2023`, `uploads/2024`, … ,
        `themes/`, `plugins/` separately and download each.)

## B. On server1 — put files in place
- [ ] 6. Create the folder: `mkdir -p ~/production/applications/gundua/backup`
- [ ] 7. Upload the whole project (Dockerfile, docker-compose.yml, docker/, .env.example)
        into `~/production/applications/gundua/`.
- [ ] 8. Put **database.sql** into `~/production/applications/gundua/backup/`.
- [ ] 9. Extract **wp-content** into `~/production/applications/gundua/backup/wp-content/`
        so you have `backup/wp-content/themes`, `.../plugins`, `.../uploads`.
- [ ] 10. Fix line endings (you edited on Windows):
         `cd ~/production/applications/gundua && dos2unix docker/* 2>/dev/null || true`

## C. On server1 — configure + launch
- [ ] 11. `cp .env.example .env` then `nano .env`:
         - set the 4 DB passwords (you invent them — NOT the old host's)
         - `TABLE_PREFIX=_ifsldf_` is already correct — leave it
         - set `SITE_URL=http://<your-server-public-ip>:5053`  (preview for now)
- [ ] 12. `docker compose build`
         (build fails to resolve packages? run the daemon-DNS fix in RUNBOOK Phase 3, rebuild)
- [ ] 13. `docker compose up -d`
- [ ] 14. `docker compose logs -f gundua` — wait for `[aio] Import complete.` then `Ctrl-C`.
- [ ] 15. `docker ps` — confirm the container shows **(healthy)** after ~1–2 min.
- [ ] 16. Browse **http://<server-ip>:5053** — the site should load (images/links may
         still point at the old domain; that's fixed at cutover).

## D. Nginx Proxy Manager — put it behind the domain
- [ ] 17. NPM ▸ **Proxy Hosts** ▸ **Add Proxy Host**:
         - Domain Names: `gunduaafrica.com`, `www.gunduaafrica.com`
         - Scheme `http` ▸ Forward Hostname/IP = **server1 LAN IP** ▸ Forward Port **5053**
         - Enable **Block Common Exploits** + **Websockets Support**
         - **SSL** tab ▸ request **Let's Encrypt** cert ▸ Force SSL + HTTP/2
- [ ] 18. NPM ▸ **Redirection Hosts** ▸ **Add Redirection Host** (the safaris 301):
         - Domain Names: `gunduaafricasafaris.com`, `www.gunduaafricasafaris.com`
         - Forward to **https** / `gunduaafrica.com`
         - HTTP Code **301 Permanent** ▸ Preserve Path **on** ▸ request Let's Encrypt SSL

## E. Go live (DNS) + finalize URL
- [ ] 19. At your domain **registrar/DNS panel**: lower TTL to **300s** (do this a few
         hours before, if you can), then point the **A record** of `gunduaafrica.com`
         (and `www`) to **server1's public IP**. Do the same A records for the
         safaris domain. Make sure server firewall allows **80 + 443**.
- [ ] 20. Edit `.env` ▸ `SITE_URL=https://gunduaafrica.com` ▸ `docker compose up -d`.
- [ ] 21. Make the DB match the live URL (one time):
         ```
         docker compose exec gundua bash -c '
           curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar;
           php wp-cli.phar --allow-root search-replace "https://gunduaafrica.com" "$WP_HOME"'
         ```
- [ ] 22. Test **https://gunduaafrica.com** in a fresh browser/incognito. Log into
         `/wp-admin`. Check a few pages, images, and the contact/booking forms.

## F. Later — hand back to the shared host
- [ ] 23. When the admin raises PMEM/EP limits and the cPanel site is healthy,
         re-point the A records back, re-import any content created during the
         outage (see RUNBOOK Phase 5), then `docker compose down` on server1.
