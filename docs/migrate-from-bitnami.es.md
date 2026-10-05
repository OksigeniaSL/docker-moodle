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

Si `www-data` no puede escribir en `/bitnami/moodledata`, la imagen le da la propiedad de todo el volumen y el log explica por qué. Con ACL POSIX en las carpetas del host (un `+` tras los permisos en `ls -l`), los permisos solos no lo dicen: míralas con `getfacl`. Una entrada `group::` sin `w` para el grupo propietario (`root` o `daemon`) deja fuera a `www-data` aunque `other` pueda escribir, porque `www-data` pertenece a esos grupos.

## Qué etiqueta elegir

| Tienes | Pasa a | Notas |
|---|---|---|
| 4.5.x | `oksigenia/moodle:4.5` | Misma rama: una actualización menor, el paso más seguro. |
| 5.0.x | `oksigenia/moodle:5.3` | Moodle 5.0 dejó de recibir parches de seguridad el 5 de octubre de 2026. La 5.3 es LTS, con parches de seguridad hasta octubre de 2029; la 5.2 los tiene hasta octubre de 2027. Elige `:5.2` solo si un plugin que necesitas aún no soporta la 5.3. |
| 4.4.x o una 4.x anterior | primero `oksigenia/moodle:4.5` | Moodle 5.2 y posteriores necesitan al menos la 4.4; pasar por la 4.5 es el camino probado. |

Moodle 5.3 también retira del núcleo el tema Classic. Al actualizar lo desinstala y reinicia todas las selecciones de ese tema en cursos, categorías, cohortes y usuarios, salvo que antes instales Classic aparte. La imagen se detiene antes de actualizar si el sitio usa Classic; con `MOODLE_ALLOW_REMOVED_PLUGINS=yes`, sigue adelante.

Pasar de 4.5 a 5.x es una actualización mayor. Moodle 5.0 quitó del núcleo el editor Atto, el Chat y la Encuesta (Survey), y su actualización los desinstala. Las actividades de Chat y Encuesta se borran con ellos, así que la imagen se detiene antes de actualizar un sitio que tenga alguna. Para conservarlas, pon en el lugar de la copia antigua la versión aparte que publica Moodle HQ ([moodle-mod_chat](https://github.com/moodlehq/moodle-mod_chat), [moodle-mod_survey](https://github.com/moodlehq/moodle-mod_survey)) y reinicia. El contenedor sigue en marcha mientras espera, así que puedes hacerlo desde él:

```sh
docker compose exec -u www-data moodle sh -c 'cd "$(mktemp -d)" &&
  curl -fsSL https://github.com/moodlehq/moodle-mod_chat/archive/refs/heads/main.tar.gz | tar -xz &&
  rm -rf /var/www/moodle/mod/chat && mv moodle-mod_chat-main /var/www/moodle/mod/chat'
docker compose restart moodle
```

Moodle actualiza entonces el Chat como un plugin más y conserva sus actividades, y las siguientes actualizaciones de la imagen lo mantienen como a cualquier otro plugin. Para la Encuesta, cambia `chat` por `survey`. La imagen no conserva Atto; si lo quieres, instálalo desde [moodle.org/plugins](https://moodle.org/plugins).

## Pasos

1. **Haz copia.** La imagen también la hace, pero guarda tu propia copia de la base de datos y de los dos volúmenes antes de cualquier actualización.

2. **Revisa tus plugins.** Comprueba en moodle.org/plugins que cada uno tiene versión para el Moodle al que vas. Un plugin que no soporta la versión nueva puede romper páginas tras la actualización, a veces solo en el navegador. Por ejemplo, Moodle 5.2 eliminó los módulos JavaScript `core/modal_factory` y `core/modal_registry` (MDL-79182), y los plugins que aún los usan pierden sus ventanas emergentes sin que el servidor dé ningún error.

3. **Cierra el sitio, si alguien lo está usando.** En el contenedor de Bitnami:

   ```sh
   docker compose exec -u daemon moodle php /opt/bitnami/moodle/admin/cli/maintenance.php --enable
   ```

   La imagen mantiene el sitio cerrado después de actualizar, así que puedes revisarlo antes de que vuelva nadie. `--enable` lo cierra para todos, administradores incluidos; con `--enableold` los administradores pueden seguir entrando y revisarlo en el navegador. Ábrelo después con `docker compose exec moodle moodle-cli maintenance --disable`.

4. **Cambia la imagen.**

   ```diff
      moodle:
   -    image: bitnamilegacy/moodle:5.0.2
   +    image: oksigenia/moodle:5.3
   ```

   Deja todo lo demás igual: las variables (`MOODLE_DATABASE_HOST`, `MOODLE_USERNAME`…), los volúmenes en `/bitnami/moodle` y `/bitnami/moodledata`, y los puertos.

5. **Recrea el contenedor y sigue los logs.**

   ```sh
   docker compose pull moodle
   docker compose up -d moodle
   docker compose logs -f moodle
   ```

   Verás los plugins que conserva, las copias, la actualización y, al final, `Moodle is ready`. Los logs también listan las variables de Bitnami en uso con su nombre nuevo.

6. **Comprueba el sitio.** Entra como administrador y revisa:
   - *Administración del sitio → Notificaciones*;
   - *Servidor → Entorno*;
   - tus plugins, en *Vista general de extensiones*.

Al pasar de 4.5 a 5.x, las primeras ejecuciones del cron tardan más: Moodle 5.0 pasa cada banco de preguntas a una actividad propia y crea cursos para guardar los compartidos. Hasta que termina, Moodle avisa de que el cron sigue en marcha, y los recuentos de cursos y actividades suben por esos cursos nuevos.

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
4. En el log verás que `mariadb-upgrade` se ejecuta una vez; usuarios y bases de datos quedan como estaban. Antes de que se ejecute, MariaDB puede mostrar `[ERROR] Incorrect definition of table mysql.column_stats`; `mariadb-upgrade` arregla esa tabla.

Si copias el directorio de datos, deja fuera `ibtmp1`. Guarda tablas temporales, MariaDB lo vuelve a crear al arrancar y en un sitio con mucho uso puede llegar a decenas de gigas.

## Fórmulas con el filtro de notación TeX

Si tu sitio usa el filtro de notación TeX, comprueba qué genera hoy sus fórmulas. Las imágenes de Bitnami traen el ImageMagick 6 de Debian 12, cuya política bloquea PostScript, así que el filtro solía recurrir al mimetex incluido sin que nadie lo notara (las imágenes en caché son GIF87a). Moodle 5.3 ya no trae mimetex. Antes de pasar a la 5.3, extiende la imagen con LaTeX (véase *Herramientas extra* en el README) y pon el preámbulo en UTF-8 si las fórmulas llevan tildes.

## Proxys que gestionan los certificados

Algunos proxys que emiten los certificados por ti (por ejemplo, nginx-proxy con acme-companion) retiran el certificado de un sitio mientras su contenedor está parado. Solo lo reponen si la autoridad de certificación responde cuando el contenedor vuelve. Haz la migración en poco tiempo y comprueba después qué certificado sirve el sitio.

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
