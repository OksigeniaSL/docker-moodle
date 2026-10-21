# Imagen de contenedor de Moodle™ por Oksigenia

Imagen de contenedor del software Moodle™ LMS, mantenida y de código abierto. Lleva el código oficial de Moodle sin modificar, con Apache y PHP configurados como recomienda Moodle.

[Read in English](README.md)

> **php2shell está corregido desde el 21 de octubre de 2026.** Los fallos de PHP CVE-2026-109618 y CVE-2026-109619 (ejecución remota de código sin iniciar sesión) están corregidos en `4.5.15-r17`, con PHP 8.3.36, y en `5.2.4-r17` y `5.3.0-r17`, con PHP 8.4.27. Las etiquetas de rama (`4.5`, `5.2`, `5.3`, `latest`…) ya apuntan a ellas. Descarga la etiqueta y vuelve a crear el contenedor:
>
> ```sh
> docker compose pull moodle && docker compose up -d moodle
> ```
>
> Si fijaste una etiqueta inmutable (`5.2.4-r16` o anterior), cámbiala por la `-r17` de tu rama.

## Qué hace

- **Parches de seguridad el mismo día.** Las versiones de Moodle, también las de seguridad, se publican el día que Moodle las anuncia, y las versiones nuevas de PHP, el día que las trae la imagen oficial de PHP.
- **Reconstrucción semanal,** para recoger los parches de Debian.
- **Se instala y se actualiza sola.** El primer arranque instala el sitio. Al cambiar la etiqueta, actualiza Moodle después de copiar la base de datos y el código.
- **Completa para Moodle 5.x:** el router de URL viene configurado y las dependencias de Composer de Moodle se instalan al compilar la imagen. El paquete oficial no las trae, la comprobación de entorno de Moodle las pide y en la 5.3 las necesitan los clientes OAuth 2.
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

## Si vienes de Bitnami

Las imágenes gratuitas de Moodle de Bitnami dejaron de actualizarse en agosto de 2025. Esta imagen acepta sus variables de entorno y su estructura de volúmenes, así que basta con cambiar una línea del Compose:

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

Los nombres de variables de Bitnami siguen funcionando, y los logs sugieren los nuevos. La migración se prueba en CI con volúmenes reales de `bitnamilegacy/moodle`. Antes de hacerlo en producción, lee la [guía de migración](docs/migrate-from-bitnami.es.md): explica las copias de seguridad, el contenedor de la base de datos, qué etiqueta elegir y cómo volver atrás.

## Etiquetas

| Moodle | Etiquetas | PHP | Seguridad hasta |
|---|---|---|---|
| 5.3 LTS | `5.3`, `5`, `latest`, `lts` | 8.4 | octubre de 2029 |
| 5.2 | `5.2` | 8.4 | octubre de 2027 |
| 4.5 LTS | `4.5`, `4` | 8.3 | octubre de 2027 |

`latest` y `5` siguen a la rama más nueva: desde el 5 de octubre de 2026 apuntan a la 5.3. Para quedarte en una rama, usa su etiqueta propia, como `5.2` o `4.5`.

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
| `MOODLE_CRON_KEEPALIVE` | intervalo − 10 | Segundos que cada ejecución sigue viva recogiendo tareas ad hoc (el `--keep-alive` de Moodle). Las ejecuciones nunca se solapan. |
| `MOODLE_CRON_LOG` | `errors` | Con `errors`, la salida del cron solo aparece cuando falla; con `full`, aparece la de todas las ejecuciones. La última ejecución siempre está en `moodledata/oksigenia/cron-last.log`. |
| `MOODLE_AUTO_UPGRADE` | `on` | Con `off`, no arranca si hace falta actualizar, para que lo hagas tú. |
| `MOODLE_BACKUP_BEFORE_UPGRADE` | `on` | Volcado de la base de datos (y archivo del código) antes de cada actualización. |
| `MOODLE_BACKUP_KEEP` | `2` | Copias que se conservan en `moodledata/oksigenia/backups`. La última tomada antes de un cambio de versión se conserva siempre. |
| `MOODLE_ALLOW_REMOVED_PLUGINS` | `no` | Con `yes`, la actualización sigue aunque vaya a desinstalar plugins que Moodle retiró del núcleo y que el sitio aún usa (actividades de Chat o Survey, el tema Classic). |
| `MOODLE_RETRY_UPGRADE` | `no` | Tras una actualización fallida, el contenedor se detiene en cada arranque, sin hacer copias nuevas, hasta que corrijas la causa y lo arranques una vez con `yes`. |
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
// Moodle 5.3+: oculta las tarjetas promocionales de Moodle HQ en la página de notificaciones del administrador.
$CFG->disablenotificationctas = ['marketplace', 'moodlecloud', 'partners', 'feedback'];
```

## Herramientas extra (LaTeX, Graphviz, LibreOffice…)

La imagen trae las herramientas que necesitan casi todos los sitios: Ghostscript y Poppler para anotar PDF en las tareas, y los clientes de base de datos para las copias. Las opcionales se quedan fuera para que pese poco. Para añadirlas, extiende la imagen; en cada arranque configura en Moodle las rutas de `latex`, `dvips`, `dvisvgm`, `convert`, `dot`, `python3` y `unoconv` que encuentre:

```dockerfile
FROM oksigenia/moodle:5.2
RUN apt-get update && apt-get install -y --no-install-recommends \
        texlive-latex-base texlive-latex-recommended dvisvgm graphviz \
    && rm -rf /var/lib/apt/lists/*
```

Constrúyela desde tu Compose con `build: .` en lugar de `image:`. La salida SVG del filtro TeX usa `dvisvgm`; las salidas PNG y GIF necesitan además ImageMagick (añade `imagemagick`).

Si la construcción no llega a los servidores de paquetes (apt, o GitHub si construyes esta misma imagen) y el host sí, lo habitual es que el IPv6 de Docker esté roto en ese host. Construye con `docker build --network host`, o con `network: host` dentro de `build:` en Compose.

Dos cosas sobre el filtro de notación TeX:
- **Desde Moodle 5.3 hace falta LaTeX.** El filtro recurría al mimetex incluido cuando LaTeX faltaba o fallaba, y Moodle 5.3 ya no trae mimetex.
- **Los textos con tildes necesitan UTF-8.** El preámbulo LaTeX por defecto de Moodle empieza con `\usepackage[latin1]{inputenc}`, y con él fallan las fórmulas que llevan tildes o eñes dentro de `\text{}`. Cámbialo por `\usepackage[utf8]{inputenc}` en *Administración del sitio → Extensiones → Filtros → Notación TeX*.

## Volúmenes, puertos y usuario

| Ruta | Contenido |
|---|---|
| `/var/www/moodle` | El código de Moodle, incluidos los plugins instalados desde la web. Debe ir en un volumen; si no, esos plugins se pierden al recrear el contenedor. |
| `/var/www/moodledata` | El directorio de datos de Moodle: ficheros, cachés y las copias que hace la imagen. |

- **Puertos:** HTTP en el 8080. HTTPS en el 8443 si se montan certificados en `/certs/tls.crt` y `/certs/tls.key`; lo habitual es terminar el TLS en un proxy inverso.
- **Usuario:** Apache y el cron corren como `www-data` (uid 33).
  - El contenedor arranca como root solo para ajustar el dueño de los volúmenes y después pasa a `www-data`.
  - También funciona sin ningún privilegio con `user: www-data`. En ese caso los volúmenes tienen que ser ya del uid 33.
  - Si arreglas los dueños en el host, recrea después el contenedor (`docker compose up -d --force-recreate`): un `up -d` normal deja el contenedor fallido reintentando.

## Actualizaciones

Para actualizar, cambia la etiqueta (por ejemplo de `5.2` a `5.3`) y recrea el contenedor. Al arrancar, la imagen compara su versión de Moodle con la del volumen de código, y si la suya es más nueva hace lo siguiente:

1. Guarda un volcado de la base de datos y un archivo del código actual en `moodledata/oksigenia/backups/`.
2. Sustituye el núcleo de Moodle y conserva tus plugins, `config.php` y todo lo que no es del núcleo.
3. Ejecuta la actualización de Moodle en modo mantenimiento, purga las cachés y arranca el sitio. Si el sitio ya estaba en mantenimiento, sigue en él, y el cron espera a que se abra.

Si el volumen tiene un Moodle más nuevo que la imagen, o uno desde el que Moodle no puede actualizar directamente, el contenedor no arranca y explica por qué. También se detiene antes de tocar nada en dos casos:
- un plugin de terceros haría que Moodle rechazara la actualización (por ejemplo, módulos que aún declaran `FEATURE_GROUPMEMBERSONLY`, que se rechazan desde la 5.3);
- la actualización desinstalaría plugins retirados del núcleo que el sitio usa. Para conservar uno, pon en su lugar una versión aparte (véase [Chat y Encuesta](docs/migrate-from-bitnami.es.md#qué-etiqueta-elegir)).

Si una actualización falla a medias, el sitio queda en modo mantenimiento y los arranques siguientes se detienen enseguida, para que un bucle de reinicios no sustituya la copia buena. Ante cualquiera de estos problemas, el contenedor no sale: se queda esperando, marcado como no sano, porque una política de reinicio solo repetiría el mismo error. Corrige la causa y reinícialo. Si varios contenedores comparten los mismos volúmenes (réplicas web, un contenedor de cron), se turnan y solo uno actualiza.

## Cron

El cron corre dentro del contenedor cada minuto, como `www-data`. Para ejecutarlo aparte, por ejemplo con varias réplicas web, pon `MOODLE_CRON=off` en los contenedores web y añade otro con la misma imagen, los mismos volúmenes y las mismas variables, y el comando `cron`:

```yaml
  moodle-cron:
    image: oksigenia/moodle:5.2
    command: cron
    # el mismo environment y los mismos volumes que el contenedor web
```

## Los scripts de línea de comandos de Moodle

`moodle-cli` ejecuta cualquier script de `admin/cli` como `www-data` y desde el directorio correcto. Desde Moodle 5.1, `admin/cli` sigue en la raíz del código, no bajo `public/`. Evita `docker exec … php admin/cli/…` sin `-u www-data`: como root, Moodle deja cachés con dueño root que Apache no puede sustituir (al reiniciar el contenedor vuelven a ser de `www-data`).

```sh
docker compose exec moodle moodle-cli maintenance --enable
docker compose exec moodle moodle-cli cfg --name=theme --set=boost
docker compose exec moodle moodle-cli admin/tool/task/cli/schedule_task.php --list
```

Los scripts de `/docker-entrypoint-init.d/` (`.sh` y `.php`) se ejecutan una vez, tras la primera instalación.

## Oksigenia Access

La imagen incluye [Oksigenia Access](https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess), un panel de accesibilidad para Moodle. Tiene 17 controles (tamaño de texto, contraste, tipografía para dislexia, guía de lectura…), 4 perfiles de un clic y 8 idiomas, y quien entra con su cuenta encuentra sus ajustes en cualquier dispositivo. Está en el [Moodle Marketplace](https://marketplace.moodle.com/plugins/local_oksigeniaaccess) con los premios *Privacy friendly* y *Automated testing support*. **No se instala si no lo pides:**

```yaml
    environment:
      OKSIGENIA_ACCESS: "on"
```

- **Activarlo:** con `on`, el plugin se instala y se activa, y la imagen lo mantiene actualizado.
- **Desactivarlo:** poner `off` más tarde lo desactiva sin borrar sus ajustes.
- **Ajustes:** en *Administración del sitio → Extensiones → Extensiones locales → Panel de accesibilidad (Oksigenia Access)*.

## Seguridad

- **Firma:** las imágenes se firman con [cosign](https://github.com/sigstore/cosign), con la identidad del workflow de publicación de este repositorio. Para verificar una imagen:

  ```sh
  cosign verify oksigenia/moodle:5.2 \
    --certificate-identity-regexp '^https://github.com/OksigeniaSL/docker-moodle/\.github/workflows/release\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

  Hace falta cosign 3, o cosign 2.6 con `--new-bundle-format`. Las versiones anteriores responden `no signatures found`.

- **SBOM y procedencia:** cada imagen lleva SBOM y atestaciones de procedencia SLSA, que se consultan con `docker buildx imagetools inspect oksigenia/moodle:5.2 --format '{{json .SBOM}}'`. También lleva la atestación de compilación de GitHub, que se verifica con `gh attestation verify oci://ghcr.io/oksigeniasl/moodle:5.2 -R OksigeniaSL/docker-moodle` (GitHub CLI 2.49 o posterior).
- **Escaneo:** no se publica ninguna compilación con una vulnerabilidad crítica que tenga parche.
- **Avisos de seguridad:**
  - Las vulnerabilidades de la imagen, en privado mediante los [avisos de seguridad de GitHub](https://github.com/OksigeniaSL/docker-moodle/security/advisories/new).
  - Las del propio Moodle, por su [proceso de seguridad](https://moodledev.io/general/development/process/security).

## Dónde están las imágenes

Las mismas imágenes se publican en Docker Hub como `oksigenia/moodle` y en GitHub como `ghcr.io/oksigeniasl/moodle`.

## Mantenida por Oksigenia

El equipo de [Oksigenia](https://oksigenia.com/servicios/moodle) trabaja con Moodle desde la versión 1.7 y mantiene esta imagen. ¿Prefieres no mantenerlo tú? Oksigenia puede alojar y mantener tu sitio Moodle.

Alojamiento gestionado para Moodle™ y rescate de sitios Bitnami, para centros educativos: [oksigenia.com/servicios/moodle](https://oksigenia.com/servicios/moodle) ([rescate de Bitnami](https://oksigenia.com/servicios/moodle#bitnami)).

## Licencia

El código de la imagen (este repositorio) se distribuye con licencia [GNU GPL v3.0](LICENSE). Moodle se distribuye con licencia GNU GPL v3 o posterior.

The word Moodle and associated Moodle logos are trademarks or registered trademarks of Moodle Pty Ltd or its related affiliates. Este proyecto no está afiliado a Moodle HQ ni cuenta con su respaldo.
