# Migrating from bitnami/moodle

This guide moves a site running `bitnami/moodle` or `bitnamilegacy/moodle` to `oksigenia/moodle` without exporting or importing anything: you keep the same Compose file, the same volumes and the same database.

[Leer en español](migrate-from-bitnami.es.md)

## What happens

When the container starts and finds a `bitnami/moodle` installation in `/bitnami/moodle`, it:

1. **Reads your configuration.** It takes the database settings from your `config.php`, as Bitnami did on every restart. The file is kept; it gains one line that loads the image's settings, and the original is saved in `/bitnami/moodle/.oksigenia/config.php.pre-oksigenia`.
2. **Backs up the database and the code.** Both go to `/bitnami/moodledata/oksigenia/backups/<date>/`.
3. **Replaces Moodle's core code** with the version in the image.
   - Your add-on plugins (themes, activities, blocks, local plugins…) are found and kept.
   - From Moodle 5.1 on, Moodle keeps its web files in a `public/` directory, and add-ons are moved there.
4. **Runs Moodle's database upgrade** and configures what newer Moodle versions expect, such as the URL router.
5. **Starts Apache and cron** as `www-data` on the same ports, 8080 and 8443.

`/bitnami/moodledata` keeps its ownership: Bitnami's files belong to `daemon`, and the image's user writes them through its groups. The code in `/bitnami/moodle` is handed to `www-data`, because its core is replaced on every upgrade. The previous tree, with its original ownership, stays in the backup, so you can go back to the Bitnami image if you need to (see [Going back](#going-back)).

## Which tag to choose

| You run | Move to | Notes |
|---|---|---|
| 4.5.x | `oksigenia/moodle:4.5` | Same branch: a patch-level update, the safest step. |
| 5.0.x | `oksigenia/moodle:5.2` or `:5.3` | Moodle 5.0 stopped receiving security fixes on 5 October 2026. |
| 4.4.x or older 4.x | `oksigenia/moodle:4.5` first | Moodle 5.2 and later need at least 4.4; going through 4.5 is the tested path. |

Moodle 5.3 also removes the Classic theme from core: during the upgrade it uninstalls Classic and resets every course, category, cohort and user selection of it, unless you install Classic separately first. The image stops before upgrading if the site uses Classic (`MOODLE_ALLOW_REMOVED_PLUGINS=yes` lets it go ahead).

Moving from 4.5 to 5.x is a major upgrade. Moodle 5.0 removed the Atto editor, Chat and Survey from core, and its upgrade uninstalls them. Chat and Survey activities are deleted with them, so the image stops before upgrading a site that has any. To keep them, put the separate release that Moodle HQ publishes ([moodle-mod_chat](https://github.com/moodlehq/moodle-mod_chat), [moodle-mod_survey](https://github.com/moodlehq/moodle-mod_survey)) in place of the old copy, and restart. The container stays up while it waits, so you can do it from there:

```sh
docker compose exec -u www-data moodle sh -c 'cd "$(mktemp -d)" &&
  curl -fsSL https://github.com/moodlehq/moodle-mod_chat/archive/refs/heads/main.tar.gz | tar -xz &&
  rm -rf /var/www/moodle/mod/chat && mv moodle-mod_chat-main /var/www/moodle/mod/chat'
docker compose restart moodle
```

Moodle then upgrades Chat as an add-on and keeps its activities, and later image updates carry it over like any other add-on. For Survey, replace `chat` with `survey`. The image does not carry Atto over; if you want it back, install it from [moodle.org/plugins](https://moodle.org/plugins).

## Steps

1. **Back up.** The image does it too, but keep your own copy of the database and the two volumes before any upgrade.

2. **Check your add-ons.** Make sure each one has a release for the Moodle version you move to (on moodle.org/plugins). An add-on that does not support the new version may break pages after the upgrade, sometimes only in the browser. For example, Moodle 5.2 removed the JavaScript modules `core/modal_factory` and `core/modal_registry` (MDL-79182), so add-ons that still use them lose their pop-up windows without any error on the server.

3. **Close the site, if people use it.** In the Bitnami container:

   ```sh
   docker compose exec -u daemon moodle php /opt/bitnami/moodle/admin/cli/maintenance.php --enable
   ```

   The image keeps the site closed after the upgrade, so you can check it before anyone comes back. `--enable` closes it to everyone, administrators included; with `--enableold` administrators can still log in and check it in the browser. Open it afterwards with `docker compose exec moodle moodle-cli maintenance --disable`.

4. **Change the image.**

   ```diff
      moodle:
   -    image: bitnamilegacy/moodle:5.0.2
   +    image: oksigenia/moodle:5.2
   ```

   Leave everything else as it is: the variables (`MOODLE_DATABASE_HOST`, `MOODLE_USERNAME`…), the volumes at `/bitnami/moodle` and `/bitnami/moodledata`, and the ports.

5. **Recreate the container and follow the logs.**

   ```sh
   docker compose pull moodle
   docker compose up -d moodle
   docker compose logs -f moodle
   ```

   You will see the add-ons it keeps, the backups, the upgrade and finally `Moodle is ready`. The logs also list the Bitnami variables in use and their new names.

6. **Check the site.** Log in as an administrator. Open *Site administration → Notifications* and *Server → Environment*, and check your add-ons in *Plugins overview*.

After a move from 4.5 to 5.x, the first cron runs take longer: Moodle 5.0 moves every question bank into an activity of its own, and creates courses to hold the shared ones. Until that ends, Moodle warns that cron is still running, and course and activity counts grow because of those new courses.

## Optional: switch to the new names

Bitnami's variables keep working; there is no deadline. When you want to tidy up:

| Bitnami | oksigenia/moodle |
|---|---|
| `MOODLE_DATABASE_TYPE` | `MOODLE_DB_TYPE` |
| `MOODLE_DATABASE_HOST` | `MOODLE_DB_HOST` |
| `MOODLE_DATABASE_PORT_NUMBER` | `MOODLE_DB_PORT` |
| `MOODLE_DATABASE_NAME` | `MOODLE_DB_NAME` |
| `MOODLE_DATABASE_USER` | `MOODLE_DB_USER` |
| `MOODLE_DATABASE_PASSWORD` | `MOODLE_DB_PASSWORD` |
| `MOODLE_USERNAME` | `MOODLE_ADMIN_USER` |
| `MOODLE_PASSWORD` | `MOODLE_ADMIN_PASSWORD` |
| `MOODLE_EMAIL` | `MOODLE_ADMIN_EMAIL` |
| `MOODLE_HOST` (+ `MOODLE_SSLPROXY`) | `MOODLE_URL` (with `https://`) |
| `MOODLE_REVERSEPROXY` | `MOODLE_REVERSE_PROXY` |
| `MOODLE_SSLPROXY` | `MOODLE_SSL_PROXY` |
| `MOODLE_SMTP_PORT_NUMBER` | `MOODLE_SMTP_PORT` |
| `MOODLE_SMTP_PROTOCOL` | `MOODLE_SMTP_SECURITY` |
| `MOODLE_CRON_MINUTES` | `MOODLE_CRON_INTERVAL` (seconds) |
| `APACHE_HTTP_PORT_NUMBER` | `APACHE_HTTP_PORT` |
| `APACHE_HTTPS_PORT_NUMBER` | `APACHE_HTTPS_PORT` |
| `PHP_*` | unchanged |

On a site that is already installed, the database settings come from `config.php`, as with Bitnami. Changing these variables later does not move the site to another database.

`MOODLE_SKIP_BOOTSTRAP` is no longer needed: the image detects an installed database by itself. The `MYSQL_CLIENT_CREATE_DATABASE_*` and `POSTGRESQL_CLIENT_CREATE_DATABASE_*` variables are ignored; let the database container create the database.

## The database container

`bitnamilegacy/mariadb` is frozen too, but nothing forces you to change it at the same time. `oksigenia/moodle` works with it as it is. When you want to move to the official `mariadb` image, do it as a separate step, with a dump and restore:

```sh
docker compose exec mariadb mariadb-dump -u root --single-transaction bitnami_moodle > moodle.sql
```

Then start `mariadb:11.4` with an empty volume and import `moodle.sql`. Moodle 5.3 needs MariaDB 11.4 or later.

A real migration also worked in place, keeping the data directory:

1. Take the dump above, then run `SET GLOBAL innodb_fast_shutdown=0;` and stop the 10.11 container cleanly.
2. `chown -R 999:999` the data directory (Bitnami's MariaDB runs as uid 1001, the official one as 999).
3. Mount it at `/var/lib/mysql` (Bitnami used `/bitnami/mariadb/data`), set `MARIADB_AUTO_UPGRADE: "1"`, and replace Bitnami's `MARIADB_CHARACTER_SET`/`MARIADB_COLLATE` with `command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`. With an empty root password, also `MARIADB_ALLOW_EMPTY_ROOT_PASSWORD: "1"`.
4. The log shows `mariadb-upgrade` running once; users and databases stay as they were. Before it runs, MariaDB may report `[ERROR] Incorrect definition of table mysql.column_stats`; `mariadb-upgrade` fixes that table.

If you copy the data directory, leave out `ibtmp1`. It holds temporary tables, MariaDB recreates it at start, and on a busy site it can reach tens of gigabytes.

## Formulas with the TeX notation filter

If your site uses the TeX notation filter, check what renders its formulas today. Bitnami's images ship ImageMagick 6 from Debian 12, whose policy blocks PostScript, so the filter often fell back to the bundled mimetex without anyone noticing (the cached images are GIF87a files). Moodle 5.3 no longer ships mimetex: extend the image with LaTeX before moving to 5.3 (see *Extra tools* in the README), and set the preamble to UTF-8 if formulas contain accented text.

## Reverse proxies that manage certificates

Some proxies that issue certificates for you (nginx-proxy with acme-companion, for example) drop a site's certificate while its container is stopped, and only restore it if the certificate authority answers when the container comes back. Keep the migration window short, and check the certificate the site serves afterwards.

## The container hostname

If your Compose file sets `hostname:` to the site's domain, remove it. Moodle sends some requests to its own address (the router checks, some tasks), and with that hostname they stay inside the container, where nothing listens on 443. The image warns about it at start.

## HTTPS on 8443

If you used Bitnami's port 8443:
- **Your own certificate:** mount it at `/certs/tls.crt` and `/certs/tls.key`, as before.
- **No certificate:** the image creates a self-signed one, as Bitnami did.

## Going back

The image keeps everything it replaces in `/bitnami/moodledata/oksigenia/backups/<date>/`:

- `database.sql.gz` (or `database.pgdump` on PostgreSQL), the database before the upgrade;
- `code.tar.gz`, the previous `/bitnami/moodle`.

To return to the Bitnami image:
1. Restore the database from that dump.
2. Restore `/bitnami/moodle` from `code.tar.gz`, as root so that the original ownership comes back. Empty the volume first, then extract the archive into it: `tar -xzpf code.tar.gz -C /bitnami/moodle`.
3. Change the `image:` line back.

A database that Moodle has already upgraded cannot be used with older Moodle code, which is why the dump is taken first.
