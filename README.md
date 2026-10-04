# Moodle™ container image by Oksigenia

A maintained, open-source container image of the Moodle™ LMS software: the official Moodle code, unmodified, with Apache and PHP set up the way Moodle recommends. It installs itself on first start, upgrades itself when you change the tag, and runs as a drop-in replacement for `bitnami/moodle`.

[Leer en español](README.es.md)

## Why this image

Bitnami's free Moodle images stopped receiving updates in August 2025 (`bitnami/moodle` was frozen on 2025-08-19, `bitnamilegacy/moodle` on 2025-08-23). Many sites still run on them, on Moodle 4.5.4 or 5.0.2, without security fixes. This image takes over:

- **Same Compose file, new image.** It accepts Bitnami's environment variables and volume layout. Change the `image:` line and your site keeps running, upgraded, with its add-on plugins. The migration is tested in CI against real `bitnamilegacy/moodle` volumes. See [Migrating from Bitnami](docs/migrate-from-bitnami.md).
- **Changing the tag really upgrades Moodle.** Before touching anything, the image backs up the database and the code.
- **Complete for Moodle 5.x:** the URL router is configured, and Moodle's Composer dependencies are installed when the image is built. The official package leaves them out; Moodle's environment check asks for them, and in 5.3 OAuth 2 clients need them.
- **Kept current:**
  - Every supported branch is rebuilt every week, to pick up Debian and PHP fixes.
  - New Moodle releases are picked up automatically.
- **Verifiable:**
  - Every image is scanned with Trivy before it is published.
  - Images are signed with cosign, without long-lived keys.
  - Each image ships an SBOM and build provenance.
- **Multi-arch:** amd64 and arm64.

## Quick start

```sh
curl -O https://raw.githubusercontent.com/OksigeniaSL/docker-moodle/main/compose.yaml
# edit MOODLE_URL and the passwords, then:
docker compose up -d
docker compose logs -f moodle      # first start: a few minutes
```

Open `MOODLE_URL` and log in as `admin` with `MOODLE_ADMIN_PASSWORD`. If you leave the admin password out, a random one is generated and printed once in the logs.

## Tags

| Moodle | Tags | PHP | Security fixes until |
|---|---|---|---|
| 5.2 | `5.2`, `5`, `latest` | 8.4 | October 2027 |
| 4.5 LTS | `4.5`, `4` | 8.3 | October 2027 |
| 5.3 LTS | `5.3`, and then `5`, `latest` and `lts` | 8.4 | October 2029 |

Moodle 5.3 is published here on the day Moodle releases it, planned for 5 October 2026. Until then, `latest` points to 5.2 and there is no `lts` tag, so that nobody moves from 4.5 to 5.3 by accident.

- **Exact version:** each branch also has a tag with the exact Moodle version (e.g. `5.2.3`), which moves with every rebuild.
- **Immutable build:** `5.2.3-r1`, `5.2.3-r2`… never move. Pin one of these in production if you want to decide when to update.
- **Support dates:** they are Moodle HQ's. A branch is dropped from the image after Moodle stops releasing security fixes for it.

## Configuration

Every variable also accepts a `_FILE` variant (e.g. `MOODLE_DB_PASSWORD_FILE=/run/secrets/db`) for Docker secrets.

### Site and database

| Variable | Default | Notes |
|---|---|---|
| `MOODLE_URL` | `http://localhost:8080` | The address users open (Moodle's `wwwroot`). |
| `MOODLE_DB_TYPE` | `mariadb` | `mariadb`, `mysqli` (MySQL), `pgsql` (PostgreSQL) or `auroramysql`. |
| `MOODLE_DB_HOST` | `db` | |
| `MOODLE_DB_PORT` | `3306` / `5432` | Depends on the type. |
| `MOODLE_DB_NAME` | `moodle` | |
| `MOODLE_DB_USER` | `moodle` | |
| `MOODLE_DB_PASSWORD` | | |
| `MOODLE_DB_PREFIX` | `mdl_` | |
| `MOODLE_REVERSE_PROXY` | `no` | Moodle's `reverseproxy`; rarely needed. |
| `MOODLE_SSL_PROXY` | `auto` | `auto` turns on Moodle's `sslproxy` when `MOODLE_URL` is https and TLS ends at a proxy in front of the container. |

### First install only

These are applied once, when the site is created, and never again. Change them later in Moodle's administration.

| Variable | Default | Notes |
|---|---|---|
| `MOODLE_ADMIN_USER` | `admin` | |
| `MOODLE_ADMIN_PASSWORD` | random, printed in the logs | |
| `MOODLE_ADMIN_EMAIL` | `admin@<host of MOODLE_URL>` | |
| `MOODLE_SITE_NAME` | `Moodle` | |
| `MOODLE_SITE_SHORTNAME` | the site name | |
| `MOODLE_LANG` | `en` | Default language; its pack is downloaded during the install. |
| `MOODLE_TIMEZONE` | | e.g. `Europe/Madrid`. Also sets PHP's timezone. |
| `MOODLE_NOREPLY_ADDRESS` | Moodle's default | |
| `MOODLE_SMTP_HOST` | | SMTP server; without it Moodle uses PHP mail. |
| `MOODLE_SMTP_PORT` | | |
| `MOODLE_SMTP_USER` | | |
| `MOODLE_SMTP_PASSWORD` | | |
| `MOODLE_SMTP_SECURITY` | | `tls`, `ssl` or empty. |

### Running

| Variable | Default | Notes |
|---|---|---|
| `MOODLE_EXTRA_LANGS` | | Extra language packs, e.g. `es,ca,eu,gl`. Installed when the list changes. |
| `MOODLE_REDIS_HOST` / `_PORT` / `_PASSWORD` | | Sessions and the application cache in Redis or Valkey. |
| `MOODLE_CRON` | `on` | `off` if cron runs in another container. |
| `MOODLE_CRON_INTERVAL` | `60` | Seconds between cron runs. |
| `MOODLE_CRON_KEEPALIVE` | interval − 10 | Seconds each run stays alive picking up ad hoc tasks (Moodle's `--keep-alive`). Runs never overlap. |
| `MOODLE_CRON_LOG` | `errors` | `errors` prints cron output only when it fails; `full` prints every run. The last run is always in `moodledata/oksigenia/cron-last.log`. |
| `MOODLE_AUTO_UPGRADE` | `on` | `off` refuses to start when an upgrade is needed, so you can run it yourself. |
| `MOODLE_BACKUP_BEFORE_UPGRADE` | `on` | Database dump (and code archive) before every upgrade. |
| `MOODLE_BACKUP_KEEP` | `2` | Backups kept in `moodledata/oksigenia/backups`. The newest one taken before a version change is always kept. |
| `MOODLE_ALLOW_REMOVED_PLUGINS` | `no` | `yes` lets an upgrade go ahead when it would uninstall plugins Moodle removed from core that the site still uses (Chat or Survey activities, the Classic theme). |
| `MOODLE_RETRY_UPGRADE` | `no` | After a failed upgrade the container stops at every start, without new backups, until you fix the cause and start it once with `yes`. |
| `OKSIGENIA_ACCESS` | `off` | See [Oksigenia Access](#oksigenia-access). |

### PHP and Apache

| Variable | Default |
|---|---|
| `PHP_MEMORY_LIMIT` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `100M` |
| `PHP_POST_MAX_SIZE` | `100M` |
| `PHP_MAX_EXECUTION_TIME` | `300` |
| `PHP_MAX_INPUT_VARS` | `5000` |
| `PHP_DATE_TIMEZONE` | `UTC` |
| `APACHE_MAX_REQUEST_WORKERS` | `50` |
| `APACHE_HTTP_PORT` | `8080` |
| `APACHE_HTTPS_PORT` | `8443` |

### Your own Moodle settings

The image writes `config.php` at every start, from the variables above. For anything else, mount PHP files into `/etc/moodle/config.d/`; they are loaded in alphabetical order:

```php
<?php // /etc/moodle/config.d/50-local.php
$CFG->debug = 0;
$CFG->forced_plugin_settings = ['theme_boost' => ['brandcolor' => '#0f6cbf']];
// Moodle 5.3+: hide Moodle HQ's promotional cards on the admin notifications page.
$CFG->disablenotificationctas = ['marketplace', 'moodlecloud', 'partners', 'feedback'];
```

## Extra tools (LaTeX, Graphviz, LibreOffice…)

The image ships the tools most sites need: Ghostscript and Poppler for assignment PDF annotation, and the database clients for backups. Optional ones are left out to keep it small. Extend the image to add them; at every start it sets Moodle's paths for any of `latex`, `dvips`, `dvisvgm`, `convert`, `dot`, `python3` and `unoconv` it finds:

```dockerfile
FROM oksigenia/moodle:5.2
RUN apt-get update && apt-get install -y --no-install-recommends \
        texlive-latex-base texlive-latex-recommended dvisvgm graphviz \
    && rm -rf /var/lib/apt/lists/*
```

Build it from your Compose file with `build: .` instead of `image:`. The TeX filter's SVG output uses `dvisvgm`; its PNG and GIF outputs also need ImageMagick (add `imagemagick`).

Two things about the TeX notation filter:
- **LaTeX is required from Moodle 5.3.** The filter used to fall back to the bundled mimetex when LaTeX was missing or failed; Moodle 5.3 no longer ships mimetex.
- **Accented text needs UTF-8.** Moodle's default LaTeX preamble starts with `\usepackage[latin1]{inputenc}`, and formulas with accented letters inside `\text{}` fail with it. Change it to `\usepackage[utf8]{inputenc}` in *Site administration → Plugins → Filters → TeX notation*.

## Volumes, ports and user

| Path | Contents |
|---|---|
| `/var/www/moodle` | Moodle code, including plugins installed from the web. Keep it in a volume, or plugins installed from the web are lost when the container is recreated. |
| `/var/www/moodledata` | Moodle's data directory: files, caches, backups made by the image. |

- **Ports:** HTTP on 8080. HTTPS on 8443 when certificates are mounted at `/certs/tls.crt` and `/certs/tls.key`; most setups terminate TLS in a reverse proxy instead.
- **User:** Apache and cron run as `www-data` (uid 33).
  - The container starts as root only to fix the ownership of the volumes, then drops to `www-data`.
  - It also runs fully unprivileged with `user: www-data`. In that case the volumes must already belong to uid 33.
  - If you fix ownership on the host instead, recreate the container afterwards (`docker compose up -d --force-recreate`): a plain `up -d` leaves the failed container retrying.

## Upgrades

To upgrade, change the tag (for example from `5.2` to `5.3`) and recreate the container. On start, the image compares the Moodle version it ships with the one in the code volume, and when the image is newer it does the following:

1. Saves a database dump and an archive of the current code in `moodledata/oksigenia/backups/`.
2. Replaces Moodle's core code and keeps your add-on plugins, `config.php` and anything else that is not core.
3. Runs Moodle's upgrade in maintenance mode, purges the caches and starts the site.

If the volume holds a newer Moodle than the image, or one Moodle cannot upgrade from directly, the container refuses to start and says why. It also stops before changing anything when an add-on would make Moodle reject the upgrade (for example modules that still declare `FEATURE_GROUPMEMBERSONLY`, refused from 5.3), or when the upgrade would uninstall plugins removed from core that the site uses (to keep one, put a separate release of it in its place; see [Chat and Survey](docs/migrate-from-bitnami.md#which-tag-to-choose)). If an upgrade fails half way, the site stays in maintenance mode and later starts stop straight away, so a restart loop cannot replace the good backup. On any of these problems the container stays up and waits, unhealthy, instead of exiting: a restart policy would only repeat the same error. Fix the cause and restart it. Several containers sharing the same volumes (web replicas, a cron container) take turns: only one upgrades.

## Cron

Cron runs inside the container every minute, as `www-data`. To run it separately, for instance with several web replicas, set `MOODLE_CRON=off` on the web containers and add one container with the same image, volumes and variables, and the command `cron`:

```yaml
  moodle-cron:
    image: oksigenia/moodle:5.2
    command: cron
    # same environment and volumes as the web container
```

## Moodle's command-line scripts

`moodle-cli` runs any script under `admin/cli` as `www-data`, from the right directory. From Moodle 5.1, `admin/cli` stays at the root of the code, not under `public/`. Avoid `docker exec … php admin/cli/…` without `-u www-data`: run as root, Moodle leaves root-owned cache files that Apache cannot replace (a restart of the container hands them back to `www-data`).

```sh
docker compose exec moodle moodle-cli maintenance --enable
docker compose exec moodle moodle-cli cfg --name=theme --set=boost
docker compose exec moodle moodle-cli admin/tool/task/cli/schedule_task.php --list
```

Scripts in `/docker-entrypoint-init.d/` (`.sh` and `.php`) run once, after the first install.

## Migrating from Bitnami

Change only the image in your Compose file:

```diff
   moodle:
-    image: bitnamilegacy/moodle:5.0.2
+    image: oksigenia/moodle:5.2
```

The image recognises the `/bitnami/moodle` and `/bitnami/moodledata` volumes, reads your existing `config.php`, keeps your add-on plugins, upgrades Moodle and keeps ports 8080 and 8443. Bitnami's variable names keep working, and the logs suggest the new names. Read the [migration guide](docs/migrate-from-bitnami.md) before doing it in production: it covers backups, the database container and rollback.

## Oksigenia Access

The image includes [Oksigenia Access](https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess), an accessibility panel for Moodle. It covers 17 controls (text size, contrast, dyslexia-friendly font, reading guide…), 4 one-click profiles and 8 languages. **It is not installed unless you ask for it:**

```yaml
    environment:
      OKSIGENIA_ACCESS: "on"
```

- **Turning it on:** with `on`, the plugin is installed and enabled, and the image keeps it updated.
- **Turning it off:** setting `off` later disables it without removing its settings.
- **Settings:** in *Site administration → Plugins → Local plugins → Oksigenia Access*.

## Security

- **Signatures:** images are signed with [cosign](https://github.com/sigstore/cosign), with the identity of this repository's release workflow. To verify an image:

  ```sh
  cosign verify oksigenia/moodle:5.2 \
    --certificate-identity-regexp '^https://github.com/OksigeniaSL/docker-moodle/\.github/workflows/release\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

  This needs cosign 3, or cosign 2.6 with `--new-bundle-format`. Older versions report `no signatures found`.

- **SBOM and provenance:** each image carries an SBOM and SLSA provenance attestations (`docker buildx imagetools inspect oksigenia/moodle:5.2 --format '{{json .SBOM}}'`), and a GitHub build attestation (`gh attestation verify oci://ghcr.io/oksigeniasl/moodle:5.2 -R OksigeniaSL/docker-moodle`, with GitHub CLI 2.49 or later).
- **Scanning:** a build with a critical vulnerability that has a fix available is not published.
- **Reporting:** report vulnerabilities in the image privately through [GitHub security advisories](https://github.com/OksigeniaSL/docker-moodle/security/advisories/new). Vulnerabilities in Moodle itself go to [Moodle's security process](https://moodledev.io/general/development/process/security).

## Images

The same images are published on Docker Hub as `oksigenia/moodle` and on GitHub as `ghcr.io/oksigeniasl/moodle`.

## Maintained by Oksigenia

The team at [Oksigenia](https://oksigenia.com/en/services/moodle) has worked with Moodle since version 1.7 and maintains this image. Prefer not to maintain it yourself? Oksigenia can host and maintain your Moodle site for you.

## License

The image's source (this repository) is licensed under the [GNU GPL v3.0](LICENSE). Moodle is distributed under the GNU GPL v3 or later.

The word Moodle and associated Moodle logos are trademarks or registered trademarks of Moodle Pty Ltd or its related affiliates. This project is not affiliated with or endorsed by Moodle HQ.
