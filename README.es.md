# Imagen de contenedor de Moodle™ por Oksigenia

Imagen de contenedor del software Moodle™ LMS, mantenida y de código abierto. Lleva el código oficial de Moodle sin modificar, con Apache y PHP configurados como recomienda Moodle. Se instala sola en el primer arranque, se actualiza sola al cambiar la etiqueta y sustituye directamente a `bitnami/moodle`.

[Read in English](README.md)

## Por qué existe

Las imágenes gratuitas de Moodle de Bitnami dejaron de actualizarse en agosto de 2025: `bitnami/moodle` se congeló el 19-08-2025 y `bitnamilegacy/moodle` el 23-08-2025. Muchos sitios siguen funcionando con ellas, en Moodle 4.5.4 o 5.0.2, sin parches de seguridad. Esta imagen toma el relevo:

- **El mismo Compose, otra imagen.** Acepta las variables de entorno y la estructura de volúmenes de Bitnami.
  - Basta con cambiar la línea `image:` para que el sitio siga funcionando, actualizado y con sus plugins.
  - La migración se prueba en CI con volúmenes reales de `bitnamilegacy/moodle`. Véase [Migrar desde Bitnami](docs/migrate-from-bitnami.es.md).
- **Cambiar la etiqueta actualiza Moodle de verdad.** Antes de tocar nada, la imagen hace copia de la base de datos y del código.
- **Al día:**
  - Todas las ramas soportadas se reconstruyen cada semana, para recoger los parches de Debian y de PHP.
  - Las versiones nuevas de Moodle se incorporan automáticamente.
- **Verificable:**
  - Cada imagen se escanea con Trivy antes de publicarse.
  - Se firma con cosign sin claves de larga duración.
  - Lleva SBOM y procedencia.
- **Multiarquitectura:** amd64 y arm64.

## Inicio rápido

```sh
curl -O https://raw.githubusercontent.com/OksigeniaSL/docker-moodle/main/compose.yaml
# cambia MOODLE_URL y las contraseñas, y después:
docker compose up -d
docker compose logs -f moodle      # el primer arranque tarda unos minutos
```

Abre `MOODLE_URL` y entra como `admin` con `MOODLE_ADMIN_PASSWORD`. Si no indicas la contraseña del administrador, se genera una al azar y aparece una sola vez en los logs.

## Etiquetas

| Moodle | Etiquetas | PHP | Seguridad hasta |
|---|---|---|---|
| 5.2 | `5.2`, `5`, `latest` | 8.4 | octubre de 2027 |
| 4.5 LTS | `4.5`, `4` | 8.3 | octubre de 2027 |
| 5.3 LTS | `5.3`, y después `5`, `latest` y `lts` | 8.4 | octubre de 2029 |

Moodle 5.3 se publica aquí el mismo día que la publique Moodle, previsto para el 5 de octubre de 2026. Hasta entonces, `latest` apunta a la 5.2 y no hay etiqueta `lts`, para que nadie pase de la 4.5 a la 5.3 sin querer.

- **Versión exacta:** cada rama tiene también una etiqueta con la versión exacta de Moodle (por ejemplo `5.2.3`), que se mueve con cada reconstrucción.
- **Compilación inmutable:** `5.2.3-r1`, `5.2.3-r2`… no se mueven nunca. Fija una de estas en producción si quieres decidir tú cuándo actualizar.
- **Fechas de soporte:** son las de Moodle HQ. Una rama sale de la imagen cuando Moodle deja de publicar parches de seguridad para ella.

## Configuración

Todas las variables admiten la variante `_FILE` para secretos de Docker; por ejemplo, `MOODLE_DB_PASSWORD_FILE=/run/secrets/db`.

### Sitio y base de datos

| Variable | Por defecto | Notas |
|---|---|---|
| `MOODLE_URL` | `http://localhost:8080` | La dirección que abren los usuarios (el `wwwroot` de Moodle). |
| `MOODLE_DB_TYPE` | `mariadb` | `mariadb`, `mysqli` (MySQL), `pgsql` (PostgreSQL) o `auroramysql`. |
| `MOODLE_DB_HOST` | `db` | |
| `MOODLE_DB_PORT` | `3306` / `5432` | Según el tipo. |
| `MOODLE_DB_NAME` | `moodle` | |
| `MOODLE_DB_USER` | `moodle` | |
| `MOODLE_DB_PASSWORD` | | |
| `MOODLE_DB_PREFIX` | `mdl_` | |
| `MOODLE_REVERSE_PROXY` | `no` | El `reverseproxy` de Moodle; rara vez hace falta. |
| `MOODLE_SSL_PROXY` | `auto` | Con `auto`, activa el `sslproxy` de Moodle si `MOODLE_URL` es https y el TLS termina en un proxy delante del contenedor. |

### Solo en la primera instalación

Se aplican una vez, al crear el sitio, y nunca más. Después se cambian en la administración de Moodle.

| Variable | Por defecto | Notas |
|---|---|---|
| `MOODLE_ADMIN_USER` | `admin` | |
| `MOODLE_ADMIN_PASSWORD` | al azar, en los logs | |
| `MOODLE_ADMIN_EMAIL` | `admin@<dominio de MOODLE_URL>` | |
| `MOODLE_SITE_NAME` | `Moodle` | |
| `MOODLE_SITE_SHORTNAME` | el nombre del sitio | |
| `MOODLE_LANG` | `en` | Idioma por defecto; su paquete se descarga durante la instalación. |
| `MOODLE_TIMEZONE` | | Por ejemplo `Europe/Madrid`. También fija la zona horaria de PHP. |
| `MOODLE_NOREPLY_ADDRESS` | el de Moodle | |
| `MOODLE_SMTP_HOST` | | Servidor SMTP; sin él, Moodle usa el correo de PHP. |
| `MOODLE_SMTP_PORT` | | |
| `MOODLE_SMTP_USER` | | |
| `MOODLE_SMTP_PASSWORD` | | |
| `MOODLE_SMTP_SECURITY` | | `tls`, `ssl` o vacío. |

### Funcionamiento

| Variable | Por defecto | Notas |
|---|---|---|
| `MOODLE_EXTRA_LANGS` | | Paquetes de idioma extra, por ejemplo `es,ca,eu,gl`. Se instalan cuando cambia la lista. |
| `MOODLE_REDIS_HOST` / `_PORT` / `_PASSWORD` | | Sesiones y caché de aplicación en Redis o Valkey. |
| `MOODLE_CRON` | `on` | `off` si el cron va en otro contenedor. |
| `MOODLE_CRON_INTERVAL` | `60` | Segundos entre ejecuciones del cron. |
| `MOODLE_CRON_LOG` | `errors` | Con `errors`, la salida del cron solo aparece cuando falla; con `full`, aparece la de todas las ejecuciones. La última ejecución siempre está en `moodledata/oksigenia/cron-last.log`. |
| `MOODLE_AUTO_UPGRADE` | `on` | Con `off`, no arranca si hace falta actualizar, para que lo hagas tú. |
| `MOODLE_BACKUP_BEFORE_UPGRADE` | `on` | Volcado de la base de datos (y archivo del código) antes de cada actualización. |
| `MOODLE_BACKUP_KEEP` | `2` | Copias que se conservan en `moodledata/oksigenia/backups`. |
| `OKSIGENIA_ACCESS` | `off` | Véase [Oksigenia Access](#oksigenia-access). |

### PHP y Apache

| Variable | Por defecto |
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

### Tus propios ajustes de Moodle

La imagen escribe `config.php` en cada arranque a partir de las variables anteriores. Para todo lo demás, monta ficheros PHP en `/etc/moodle/config.d/`; se cargan por orden alfabético:

```php
<?php // /etc/moodle/config.d/50-local.php
$CFG->debug = 0;
$CFG->forced_plugin_settings = ['theme_boost' => ['brandcolor' => '#0f6cbf']];
```

## Volúmenes, puertos y usuario

| Ruta | Contenido |
|---|---|
| `/var/www/moodle` | El código de Moodle, incluidos los plugins instalados desde la web. Debe ir en un volumen; si no, esos plugins se pierden al recrear el contenedor. |
| `/var/www/moodledata` | El directorio de datos de Moodle: ficheros, cachés y las copias que hace la imagen. |

- **Puertos:** HTTP en el 8080. HTTPS en el 8443 si se montan certificados en `/certs/tls.crt` y `/certs/tls.key`; lo habitual es terminar el TLS en un proxy inverso.
- **Usuario:** Apache y el cron corren como `www-data` (uid 33).
  - El contenedor arranca como root solo para ajustar el dueño de los volúmenes y después pasa a `www-data`.
  - También funciona sin ningún privilegio con `user: www-data`. En ese caso los volúmenes tienen que ser ya del uid 33.

## Actualizaciones

Para actualizar, cambia la etiqueta (por ejemplo de `5.2` a `5.3`) y recrea el contenedor. Al arrancar, la imagen compara su versión de Moodle con la del volumen de código, y si la suya es más nueva hace lo siguiente:

1. Guarda un volcado de la base de datos y un archivo del código actual en `moodledata/oksigenia/backups/`.
2. Sustituye el núcleo de Moodle y conserva tus plugins, `config.php` y todo lo que no es del núcleo.
3. Ejecuta la actualización de Moodle en modo mantenimiento, purga las cachés y arranca el sitio.

Si el volumen tiene un Moodle más nuevo que la imagen, o uno desde el que Moodle no puede actualizar directamente, el contenedor no arranca y explica por qué. Si varios contenedores comparten los mismos volúmenes (réplicas web, un contenedor de cron), se turnan y solo uno actualiza.

## Cron

El cron corre dentro del contenedor cada minuto, como `www-data`. Para ejecutarlo aparte, por ejemplo con varias réplicas web, pon `MOODLE_CRON=off` en los contenedores web y añade otro con la misma imagen, los mismos volúmenes y las mismas variables, y el comando `cron`:

```yaml
  moodle-cron:
    image: oksigenia/moodle:5.2
    command: cron
    # el mismo environment y los mismos volumes que el contenedor web
```

## Los scripts de línea de comandos de Moodle

`moodle-cli` ejecuta cualquier script de `admin/cli` con el usuario y desde el directorio correctos:

```sh
docker compose exec moodle moodle-cli maintenance --enable
docker compose exec moodle moodle-cli cfg --name=theme --set=boost
docker compose exec moodle moodle-cli admin/tool/task/cli/schedule_task.php --list
```

Los scripts de `/docker-entrypoint-init.d/` (`.sh` y `.php`) se ejecutan una vez, tras la primera instalación.

## Migrar desde Bitnami

Cambia solo la imagen en tu Compose:

```diff
   moodle:
-    image: bitnamilegacy/moodle:5.0.2
+    image: oksigenia/moodle:5.2
```

La imagen hace lo siguiente:
- reconoce los volúmenes `/bitnami/moodle` y `/bitnami/moodledata`;
- lee tu `config.php` y conserva tus plugins;
- actualiza Moodle;
- mantiene los puertos 8080 y 8443.

Los nombres de variables de Bitnami siguen funcionando, y los logs sugieren los nuevos. Antes de hacerlo en producción, lee la [guía de migración](docs/migrate-from-bitnami.es.md): explica las copias de seguridad, el contenedor de la base de datos y cómo volver atrás.

## Oksigenia Access

La imagen incluye [Oksigenia Access](https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess), un panel de accesibilidad para Moodle. Tiene 15 controles (tamaño de texto, contraste, tipografía para dislexia, guía de lectura…) y 8 idiomas. **No se instala si no lo pides:**

```yaml
    environment:
      OKSIGENIA_ACCESS: "on"
```

- **Activarlo:** con `on`, el plugin se instala y se activa, y la imagen lo mantiene actualizado.
- **Desactivarlo:** poner `off` más tarde lo desactiva sin borrar sus ajustes.
- **Ajustes:** en *Administración del sitio → Extensiones → Extensiones locales → Oksigenia Access*.

## Seguridad

- **Firma:** las imágenes se firman con [cosign](https://github.com/sigstore/cosign), con la identidad del workflow de publicación de este repositorio. Para verificar una imagen:

  ```sh
  cosign verify oksigenia/moodle:5.2 \
    --certificate-identity-regexp '^https://github.com/OksigeniaSL/docker-moodle/\.github/workflows/release\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

- **SBOM y procedencia:** cada imagen lleva SBOM y atestaciones de procedencia SLSA, que se consultan con `docker buildx imagetools inspect oksigenia/moodle:5.2 --format '{{json .SBOM}}'`. También lleva la atestación de compilación de GitHub, que se verifica con `gh attestation verify oci://ghcr.io/oksigeniasl/moodle:5.2 -R OksigeniaSL/docker-moodle`.
- **Escaneo:** no se publica ninguna compilación con una vulnerabilidad crítica que tenga parche.
- **Avisos de seguridad:**
  - Las vulnerabilidades de la imagen, en privado mediante los [avisos de seguridad de GitHub](https://github.com/OksigeniaSL/docker-moodle/security/advisories/new).
  - Las del propio Moodle, por su [proceso de seguridad](https://moodledev.io/general/development/process/security).

## Dónde están las imágenes

Las mismas imágenes se publican en Docker Hub como `oksigenia/moodle` y en GitHub como `ghcr.io/oksigeniasl/moodle`.

## Mantenida por Oksigenia

El equipo de [Oksigenia](https://oksigenia.com) trabaja con Moodle desde la versión 1.7 y mantiene esta imagen. ¿Prefieres no mantenerlo tú? Oksigenia puede alojar y mantener tu sitio Moodle.

## Licencia

El código de la imagen (este repositorio) se distribuye con licencia [GNU GPL v3.0](LICENSE). Moodle se distribuye con licencia GNU GPL v3 o posterior.

The word Moodle and associated Moodle logos are trademarks or registered trademarks of Moodle Pty Ltd or its related affiliates. Este proyecto no está afiliado a Moodle HQ ni cuenta con su respaldo.
