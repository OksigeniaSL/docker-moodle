# Shared by the HTTP and HTTPS virtual hosts. MOODLE_DOCROOT is exported by
# the entrypoint: the code directory itself up to Moodle 5.0, and its
# public/ subdirectory from Moodle 5.1 on.

ServerName ${APACHE_SERVER_NAME}
DocumentRoot ${MOODLE_DOCROOT}

# Logs go to the container output through a pipe: Apache runs as www-data
# and cannot reopen /dev/stdout or /dev/stderr, which belong to root.
ErrorLog "|/usr/bin/cat"
CustomLog "|/usr/bin/cat" combined env=!moodle_nolog

AcceptPathInfo On

<Directory ${MOODLE_DOCROOT}>
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
    DirectoryIndex index.php index.html
    # Moodle router (4.5+): requests that match no file or directory go to
    # r.php. mod_rewrite rather than FallbackResource, because PHP's handler
    # takes nonexistent *.php URLs (Moodle's shims) before the fallback runs.
    RewriteEngine On
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^ /r.php [L,QSA]
</Directory>

# Files Moodle recommends never serving over the web.
RedirectMatch 404 "/\.(?!well-known/)"
RedirectMatch 404 "/(vendor|node_modules)/"
RedirectMatch 404 "/tests/(behat|fixtures)/"
RedirectMatch 404 "/fixtures/"
RedirectMatch 404 "(?i)/(composer\.(json|lock)|package(-lock)?\.json|npm-shrinkwrap\.json|Gruntfile\.js|phpunit\.xml(\.dist)?|environment\.xml|install\.xml|upgrade\.txt|UPGRADING\.md|thirdpartylibs\.xml|readme(_moodle)?(\.(txt|md))?|moodle_readme\.txt)$"
RedirectMatch 404 "\.lock$"
# Copies of config.php (config.php.bak, config.php~...) would leak secrets.
RedirectMatch 404 "/config\.php.+$"

# Container health endpoint, reachable only from inside the container.
Alias /_oksigenia/health /usr/local/lib/oksigenia-moodle/php/health.php
<Directory /usr/local/lib/oksigenia-moodle/php>
    Require all denied
    <Files health.php>
        Require local
    </Files>
</Directory>
