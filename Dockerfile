# syntax=docker/dockerfile:1
#
# Moodle(TM) LMS container image maintained by Oksigenia.
# https://github.com/OksigeniaSL/docker-moodle
#
# CI passes the build arguments for each supported branch from versions.json.

ARG PHP_VERSION=8.4

# ---------------------------------------------------------------------------
# Stage 1: fetch and verify the official Moodle package and the optional
# Oksigenia Access plugin. Nothing from this stage runs in the final image.
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-apache-trixie AS sources

ARG MOODLE_VERSION
ARG MOODLE_SHA256
# Only for testing a release before Moodle publishes its package.
ARG MOODLE_TGZ_URL=""
ARG ACCESS_VERSION
ARG ACCESS_SHA256

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN test -n "${MOODLE_VERSION}" && test -n "${MOODLE_SHA256}"; \
    # Official packages live under stableXYZ, e.g. 5.2.3 -> stable502.
    major="${MOODLE_VERSION%%.*}"; rest="${MOODLE_VERSION#*.}"; minor="${rest%%.*}"; \
    stable="stable${major}$(printf '%02d' "${minor}")"; \
    url="${MOODLE_TGZ_URL:-https://download.moodle.org/download.php/direct/${stable}/moodle-${MOODLE_VERSION}.tgz}"; \
    curl -fsSL --retry 5 -o /tmp/moodle.tgz "${url}"; \
    echo "${MOODLE_SHA256}  /tmp/moodle.tgz" | sha256sum -c -; \
    mkdir -p /usr/src/moodle; \
    tar -xzf /tmp/moodle.tgz -C /usr/src/moodle --strip-components=1 --no-same-owner; \
    rm /tmp/moodle.tgz

# From Moodle 5.1, part of Moodle's libraries come through Composer and the
# official package does not include them (Moodle's environment check warns).
# Install them from Moodle's own composer.lock, the way Moodle documents it.
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
WORKDIR /usr/src/moodle
# hadolint ignore=SC2016
RUN if php -r '$c = json_decode(file_get_contents("composer.json"), true); \
        foreach (array_keys($c["require"] ?? []) as $p) { if (!preg_match("/^(php|ext-|lib-)/", $p)) exit(0); } exit(1);'; then \
        apt-get update; apt-get install -y --no-install-recommends unzip; \
        COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --classmap-authoritative --no-interaction \
            --no-progress --ignore-platform-req='ext-*'; \
        rm -rf /root/.composer /root/.cache /var/lib/apt/lists/*; \
    fi

RUN test -n "${ACCESS_VERSION}" && test -n "${ACCESS_SHA256}"; \
    curl -fsSL --retry 5 -o /tmp/access.tgz \
        "https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess/archive/refs/tags/v${ACCESS_VERSION}.tar.gz"; \
    echo "${ACCESS_SHA256}  /tmp/access.tgz" | sha256sum -c -; \
    mkdir -p /usr/src/oksigenia-access; \
    tar -xzf /tmp/access.tgz -C /usr/src/oksigenia-access --strip-components=1 --no-same-owner; \
    rm -rf /tmp/access.tgz /usr/src/oksigenia-access/.github

# ---------------------------------------------------------------------------
# Stage 2: runtime image.
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-apache-trixie

# Locales generated at build time, so that language packs can use them.
# Add more with --build-arg EXTRA_LOCALES="sv_SE.UTF-8 da_DK.UTF-8".
ARG LOCALES="en_US.UTF-8 en_AU.UTF-8 en_GB.UTF-8 es_ES.UTF-8 es_MX.UTF-8 ca_ES.UTF-8 gl_ES.UTF-8 eu_ES.UTF-8 pt_PT.UTF-8 pt_BR.UTF-8 fr_FR.UTF-8 de_DE.UTF-8 it_IT.UTF-8 nl_NL.UTF-8 pl_PL.UTF-8 ro_RO.UTF-8 cs_CZ.UTF-8 ru_RU.UTF-8 uk_UA.UTF-8 tr_TR.UTF-8 el_GR.UTF-8 ar_SA.UTF-8 he_IL.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 zh_CN.UTF-8 zh_TW.UTF-8"
ARG EXTRA_LOCALES=""

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# PHP extensions required or recommended by Moodle. Build dependencies,
# including the compilers shipped by the base image, are purged afterwards
# so that the runtime image carries no toolchain.
# hadolint ignore=SC2086
RUN savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libicu-dev libldap-dev libpq-dev libxml2-dev libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap --with-libdir="lib/$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-install -j"$(nproc)" exif gd intl ldap mysqli opcache pgsql soap zip; \
    pecl install apcu igbinary; \
    pecl install -D 'enable-redis-igbinary="yes" enable-redis-lzf="no" enable-redis-zstd="no" enable-redis-msgpack="no" enable-redis-lz4="no"' redis; \
    docker-php-ext-enable apcu igbinary redis; \
    rm -rf /tmp/pear ~/.pearrc; \
    # Keep the base packages plus the shared libraries the new extensions
    # link against; drop the -dev packages and the toolchain.
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark > /dev/null; \
    find /usr/local -type f -name '*.so' -exec ldd '{}' ';' 2>/dev/null \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u | xargs -r dpkg-query --search 2>/dev/null | cut -d: -f1 | sort -u \
        | xargs -r apt-mark manual > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
        autoconf dpkg-dev file g++ gcc libc6-dev make pkg-config re2c; \
    for ext in apcu exif gd igbinary intl ldap mysqli pgsql redis soap sodium zip 'Zend OPcache'; do \
        php -m | grep -qixF "${ext}" || { echo "missing PHP extension: ${ext}" >&2; exit 1; }; \
    done; \
    rm -rf /var/lib/apt/lists/*

# Runtime tools: database clients for pre-upgrade backups, PDF tools for
# assignment annotation, tini as init, and locales.
# The PostgreSQL client comes from PGDG so it can back up any server version
# up to the newest one.
RUN apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ghostscript locales mariadb-client openssl poppler-utils postgresql-client-18 procps tini; \
    for l in ${LOCALES} ${EXTRA_LOCALES}; do echo "${l} UTF-8" >> /etc/locale.gen; done; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*

ENV PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=100M \
    PHP_POST_MAX_SIZE=100M \
    PHP_MAX_EXECUTION_TIME=300 \
    PHP_MAX_INPUT_TIME=300 \
    PHP_MAX_INPUT_VARS=5000 \
    PHP_DATE_TIMEZONE=UTC \
    PHP_ENABLE_OPCACHE=1 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=192 \
    APACHE_MAX_REQUEST_WORKERS=50 \
    APACHE_SERVER_TOKENS=Prod \
    APACHE_SERVER_NAME=localhost \
    APACHE_HTTP_PORT=8080 \
    APACHE_HTTPS_PORT=8443 \
    MOODLE_TLS_CERT=/certs/tls.crt \
    MOODLE_TLS_KEY=/certs/tls.key \
    MOODLE_DOCROOT=/var/www/moodle/public \
    MOODLE_CODE_DIR=/var/www/moodle \
    LANG=C.UTF-8

# Declared here, not at the top of the stage, so that a new Moodle version
# does not invalidate the cached PHP layers above.
ARG MOODLE_VERSION
ARG ACCESS_VERSION

# The official Moodle code, untouched, plus the optional Access plugin.
# The entrypoint copies the code into the code volume and keeps it updated.
COPY --from=sources /usr/src/moodle /usr/src/moodle
COPY --from=sources /usr/src/oksigenia-access /usr/src/oksigenia-access
COPY rootfs/ /

# www-data joins groups root (0) and daemon (1) so it can read and write
# volumes created by bitnami/moodle (owned by daemon:root, 775/664, with
# config.php as root:daemon 640) without changing their ownership.
RUN usermod -a -G root,daemon www-data; \
    a2dismod -f mpm_event mpm_worker > /dev/null 2>&1 || true; \
    a2enmod -q mpm_prefork headers rewrite ssl; \
    a2disconf -q other-vhosts-access-log serve-cgi-bin || true; \
    a2enconf -q zz-moodle; \
    a2dissite -q 000-default; \
    a2ensite -q moodle; \
    mkdir -p /var/www/moodle /var/www/moodledata /etc/moodle/config.d; \
    chown www-data:www-data /var/www /var/www/moodle /var/www/moodledata /etc/moodle /etc/moodle/config.d; \
    chmod 0775 /var/www; \
    chmod 0770 /var/www/moodle /var/www/moodledata; \
    # Familiar paths for people coming from bitnami/moodle.
    install -d /opt/bitnami/php/bin; \
    ln -s /var/www/moodle /opt/bitnami/moodle; \
    ln -s /usr/local/bin/php /opt/bitnami/php/bin/php; \
    chmod 0755 /usr/local/bin/docker-entrypoint /usr/local/bin/moodle-cli /usr/local/bin/moodle-healthcheck /usr/local/lib/oksigenia-moodle/run.sh; \
    echo "${MOODLE_VERSION}" > /usr/src/moodle/.oksigenia-image-version; \
    echo "${ACCESS_VERSION}" > /usr/src/oksigenia-access/.oksigenia-image-version; \
    apache2ctl -t 2>&1 | grep -q 'Syntax OK'

LABEL org.opencontainers.image.title="Moodle(TM) LMS by Oksigenia" \
      org.opencontainers.image.description="Maintained container image of the Moodle(TM) LMS software. Not affiliated with Moodle HQ." \
      org.opencontainers.image.vendor="Oksigenia SL" \
      org.opencontainers.image.url="https://oksigenia.com" \
      org.opencontainers.image.source="https://github.com/OksigeniaSL/docker-moodle" \
      org.opencontainers.image.documentation="https://github.com/OksigeniaSL/docker-moodle#readme" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.version="${MOODLE_VERSION}" \
      com.oksigenia.moodle.access.version="${ACCESS_VERSION}"

EXPOSE 8080 8443
WORKDIR /var/www/moodle
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=10s --start-period=15m --retries=3 CMD ["moodle-healthcheck"]

# The container starts as root only to fix volume permissions when needed;
# Apache and cron always run as www-data. It also runs unprivileged with
# `--user www-data` (`user: www-data` in Compose).
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "docker-entrypoint"]
CMD ["all"]
