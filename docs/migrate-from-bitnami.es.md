# Migrar desde bitnami/moodle

Esta guía pasa un sitio que funciona con `bitnami/moodle` o `bitnamilegacy/moodle` a `oksigenia/moodle` sin exportar ni importar nada. Mantienes el mismo Compose, los mismos volúmenes y la misma base de datos.

[Read in English](migrate-from-bitnami.md)

## Qué ocurre

Cuando el contenedor arranca y encuentra una instalación de `bitnami/moodle` en `/bitnami/moodle`:

1. **Lee tu configuración.** Toma los datos de la base de datos de tu `config.php`, igual que Bitnami en cada reinicio. El fichero se conserva; solo se le añade una línea que carga los ajustes de la imagen, y el original queda guardado en `/bitnami/moodle/.oksigenia/config.php.pre-oksigenia`.
2. **Hace copia de la base de datos y del código** en `/bitnami/moodledata/oksigenia/backups/<fecha>/`.
3. **Sustituye el núcleo de Moodle** por la versión de la imagen.
   - Localiza y conserva tus plugins (temas, actividades, bloques, plugins locales…).
   - Desde Moodle 5.1, Moodle guarda sus ficheros web en un directorio `public/`, y los plugins se mueven allí.
4. **Ejecuta la actualización de la base de datos de Moodle** y configura lo que esperan las versiones nuevas, como el router de URL.
5. **Arranca Apache y el cron** como `www-data`, en los mismos puertos 8080 y 8443.

`/bitnami/moodledata` conserva sus dueños: los ficheros de Bitnami son de `daemon`, y el usuario de la imagen los escribe gracias a sus grupos. El código de `/bitnami/moodle` pasa a `www-data`, porque su núcleo se sustituye en cada actualización. El árbol anterior, con sus dueños originales, queda en la copia, así que puedes volver a la imagen de Bitnami si lo necesitas (véase [Volver atrás](#volver-atrás)).

## Qué etiqueta elegir

| Tienes | Pasa a | Notas |
|---|---|---|
| 4.5.x | `oksigenia/moodle:4.5` | Misma rama: una actualización menor, el paso más seguro. |
| 5.0.x | `oksigenia/moodle:5.2` o `:5.3` | Moodle 5.0 dejó de recibir parches de seguridad el 5 de octubre de 2026. |
| 4.4.x o una 4.x anterior | primero `oksigenia/moodle:4.5` | Moodle 5.2 y posteriores necesitan al menos la 4.4; pasar por la 4.5 es el camino probado. |

Moodle 5.3 también retira del núcleo el tema Classic. Al actualizar lo desinstala y reinicia todas las selecciones de ese tema en cursos, categorías, cohortes y usuarios, salvo que antes instales Classic aparte. La imagen se detiene antes de actualizar si el sitio usa Classic; con `MOODLE_ALLOW_REMOVED_PLUGINS=yes`, sigue adelante.

Pasar de 4.5 a 5.x es una actualización mayor. Moodle 5.0 quitó del núcleo el editor Atto, el Chat y la Encuesta (Survey). Si los usas, instálalos desde [moodle.org/plugins](https://moodle.org/plugins) antes o después de actualizar. La imagen avisa de ellos y no conserva las copias antiguas.

## Pasos

1. **Haz copia.** La imagen también la hace, pero guarda tu propia copia de la base de datos y de los dos volúmenes antes de cualquier actualización.

2. **Revisa tus plugins.** Comprueba en moodle.org/plugins que cada uno tiene versión para el Moodle al que vas. Un plugin que no soporta la versión nueva puede romper páginas tras la actualización, a veces solo en el navegador. Por ejemplo, Moodle 5.2 eliminó los módulos JavaScript `core/modal_factory` y `core/modal_registry` (MDL-79182), y los plugins que aún los usan pierden sus ventanas emergentes sin que el servidor dé ningún error.

3. **Cambia la imagen.**

   ```diff
      moodle:
   -    image: bitnamilegacy/moodle:5.0.2
   +    image: oksigenia/moodle:5.2
   ```

   Deja todo lo demás igual: las variables (`MOODLE_DATABASE_HOST`, `MOODLE_USERNAME`…), los volúmenes en `/bitnami/moodle` y `/bitnami/moodledata`, y los puertos.

4. **Recrea el contenedor y sigue los logs.**

   ```sh
   docker compose pull moodle
   docker compose up -d moodle
   docker compose logs -f moodle
   ```

   Verás los plugins que conserva, las copias, la actualización y, al final, `Moodle is ready`. Los logs también listan las variables de Bitnami en uso con su nombre nuevo.

5. **Comprueba el sitio.** Entra como administrador y revisa:
   - *Administración del sitio → Notificaciones*;
   - *Servidor → Entorno*;
   - tus plugins, en *Vista general de extensiones*.

## Opcional: pasar a los nombres nuevos

Las variables de Bitnami siguen funcionando y no hay fecha límite. Cuando quieras ordenarlo:

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
| `MOODLE_HOST` (+ `MOODLE_SSLPROXY`) | `MOODLE_URL` (con `https://`) |
| `MOODLE_REVERSEPROXY` | `MOODLE_REVERSE_PROXY` |
| `MOODLE_SSLPROXY` | `MOODLE_SSL_PROXY` |
| `MOODLE_SMTP_PORT_NUMBER` | `MOODLE_SMTP_PORT` |
| `MOODLE_SMTP_PROTOCOL` | `MOODLE_SMTP_SECURITY` |
| `MOODLE_CRON_MINUTES` | `MOODLE_CRON_INTERVAL` (en segundos) |
| `APACHE_HTTP_PORT_NUMBER` | `APACHE_HTTP_PORT` |
| `APACHE_HTTPS_PORT_NUMBER` | `APACHE_HTTPS_PORT` |
| `PHP_*` | sin cambios |

En un sitio ya instalado, los datos de la base de datos salen de `config.php`, como con Bitnami. Cambiar después estas variables no mueve el sitio a otra base de datos.

`MOODLE_SKIP_BOOTSTRAP` ya no hace falta: la imagen detecta sola una base de datos instalada. Las variables `MYSQL_CLIENT_CREATE_DATABASE_*` y `POSTGRESQL_CLIENT_CREATE_DATABASE_*` se ignoran; deja que cree la base de datos su propio contenedor.

## El contenedor de la base de datos

`bitnamilegacy/mariadb` también está congelada, pero nada te obliga a cambiarla a la vez. `oksigenia/moodle` funciona con ella tal cual. Cuando quieras pasar a la imagen oficial `mariadb`, hazlo como un paso aparte, con volcado y restauración:

```sh
docker compose exec mariadb mariadb-dump -u root --single-transaction bitnami_moodle > moodle.sql
```

Después arranca `mariadb:11.4` con un volumen vacío e importa `moodle.sql`. Moodle 5.3 necesita MariaDB 11.4 o posterior.

En una migración real también funcionó sobre el mismo directorio de datos:

1. Haz el volcado de arriba, ejecuta `SET GLOBAL innodb_fast_shutdown=0;` y para limpiamente el contenedor 10.11.
2. Haz `chown -R 999:999` del directorio de datos: la MariaDB de Bitnami corre con el uid 1001 y la oficial con el 999.
3. Móntalo en `/var/lib/mysql` (Bitnami usaba `/bitnami/mariadb/data`) y pon `MARIADB_AUTO_UPGRADE: "1"`.
   - Sustituye `MARIADB_CHARACTER_SET` y `MARIADB_COLLATE` de Bitnami por `command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`.
   - Si la contraseña de root está vacía, añade también `MARIADB_ALLOW_EMPTY_ROOT_PASSWORD: "1"`.
4. En el log verás que `mariadb-upgrade` se ejecuta una vez; usuarios y bases de datos quedan como estaban.

## El nombre de host del contenedor

Si tu Compose fija `hostname:` con el dominio del sitio, quítalo. Moodle hace algunas peticiones a su propia dirección (las comprobaciones del router, algunas tareas), y con ese nombre de host se quedan dentro del contenedor, donde nadie escucha en el 443. La imagen avisa al arrancar.

## HTTPS en el 8443

Si usabas el puerto 8443 de Bitnami:
- **Con tu propio certificado:** móntalo en `/certs/tls.crt` y `/certs/tls.key`, como antes.
- **Sin certificado:** la imagen crea uno autofirmado, como hacía Bitnami.

## Volver atrás

La imagen guarda todo lo que sustituye en `/bitnami/moodledata/oksigenia/backups/<fecha>/`:

- `database.sql.gz` (o `database.pgdump` en PostgreSQL), la base de datos antes de actualizar;
- `code.tar.gz`, el `/bitnami/moodle` anterior.

Para volver a la imagen de Bitnami:
1. Restaura la base de datos con ese volcado.
2. Restaura `/bitnami/moodle` desde `code.tar.gz`, como root para que vuelvan los dueños originales. Vacía antes el volumen y después extrae el archivo dentro: `tar -xzpf code.tar.gz -C /bitnami/moodle`.
3. Vuelve a poner la línea `image:` anterior.

Una base de datos que Moodle ya ha actualizado no sirve con el código de un Moodle anterior; por eso el volcado se hace primero.
