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

The volumes keep their ownership. Bitnami's files belong to `daemon:root`; the image's user can write them through its groups. That way you can go back to the Bitnami image if you need to (see [Going back](#going-back)).

## Which tag to choose

| You run | Move to | Notes |
|---|---|---|
| 4.5.x | `oksigenia/moodle:4.5` | Same branch: a patch-level update, the safest step. |
| 5.0.x | `oksigenia/moodle:5.2` or `:5.3` | Moodle 5.0 stopped receiving security fixes on 5 October 2026. |
| 4.4.x or older 4.x | `oksigenia/moodle:4.5` first | Moodle 5.2 and later need at least 4.4; going through 4.5 is the tested path. |

Moving from 4.5 to 5.x is a major upgrade. Moodle 5.0 removed the Atto editor, Chat and Survey from core. If you use them, install them from [moodle.org/plugins](https://moodle.org/plugins) before or after the upgrade. The image warns about them and does not carry the old copies over.

## Steps

1. **Back up.** The image does it too, but keep your own copy of the database and the two volumes before any upgrade.

2. **Check your add-ons.** Make sure each one has a release for the Moodle version you move to (on moodle.org/plugins). An add-on that does not support the new version may break pages after the upgrade.

3. **Change the image.**

   ```diff
      moodle:
   -    image: bitnamilegacy/moodle:5.0.2
   +    image: oksigenia/moodle:5.2
   ```

   Leave everything else as it is: the variables (`MOODLE_DATABASE_HOST`, `MOODLE_USERNAME`…), the volumes at `/bitnami/moodle` and `/bitnami/moodledata`, and the ports.

4. **Recreate the container and follow the logs.**

   ```sh
   docker compose pull moodle
   docker compose up -d moodle
   docker compose logs -f moodle
   ```

   You will see the add-ons it keeps, the backups, the upgrade and finally `Moodle is ready`. The logs also list the Bitnami variables in use and their new names.

5. **Check the site.** Log in as an administrator. Open *Site administration → Notifications* and *Server → Environment*, and check your add-ons in *Plugins overview*.

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

## HTTPS on 8443

If you used Bitnami's port 8443:
- **Your own certificate:** mount it at `/certs/tls.crt` and `/certs/tls.key`, as before.
- **No certificate:** the image creates a self-signed one, as Bitnami did.

## Going back

The image does not change the ownership of your volumes, and it keeps everything it replaces in `/bitnami/moodledata/oksigenia/backups/<date>/`:

- `database.sql.gz` (or `database.pgdump` on PostgreSQL), the database before the upgrade;
- `code.tar.gz`, the previous `/bitnami/moodle`.

To return to the Bitnami image:
1. Restore the database from that dump.
2. Restore `/bitnami/moodle` from `code.tar.gz`.
3. Change the `image:` line back.

A database that Moodle has already upgraded cannot be used with older Moodle code, which is why the dump is taken first.
