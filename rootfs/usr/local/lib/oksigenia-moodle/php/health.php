<?php
// Container health check, served only to 127.0.0.1 (see moodle-vhost.inc).
//
// Loads config.php without the rest of Moodle's bootstrap, so it does not
// depend on the request matching wwwroot, then checks that the database
// answers and that it is not waiting for an upgrade.

define('ABORT_AFTER_CONFIG', true);

header('Content-Type: text/plain');
header('Cache-Control: no-store');

function unhealthy(string $why): void {
    http_response_code(503);
    exit("$why\n");
}

// In CLI maintenance mode Moodle answers every web request with its
// maintenance page (503) while config.php loads. The site is closed on
// purpose and the container works, so that counts as healthy.
if (is_file(rtrim(getenv('MOODLE_DATA_DIR') ?: '/var/www/moodledata', '/') . '/climaintenance.html')) {
    exit("OK\n");
}

$config = rtrim(getenv('MOODLE_CODE_DIR') ?: '/var/www/moodle', '/') . '/config.php';
if (!is_readable($config)) {
    unhealthy('not configured');
}

try {
    require($config);
    global $CFG;
    $table = $CFG->prefix . 'config';
    $port = (int) ($CFG->dboptions['dbport'] ?? 0);
    if ($CFG->dbtype === 'pgsql') {
        $conn = @pg_connect(sprintf("host='%s' port=%d dbname='%s' user='%s' password='%s' connect_timeout=5",
            addcslashes($CFG->dbhost, "'\\"), $port ?: 5432, addcslashes($CFG->dbname, "'\\"),
            addcslashes($CFG->dbuser, "'\\"), addcslashes($CFG->dbpass, "'\\")));
        if (!$conn) {
            unhealthy('database unreachable');
        }
        $res = @pg_query($conn, "SELECT value FROM $table WHERE name = 'version'");
        $dbversion = $res ? (pg_fetch_row($res)[0] ?? null) : null;
    } else {
        mysqli_report(MYSQLI_REPORT_OFF);
        $conn = mysqli_init();
        $conn->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
        if (!@$conn->real_connect($CFG->dbhost, $CFG->dbuser, $CFG->dbpass, $CFG->dbname,
                $port ?: 3306, ($CFG->dboptions['dbsocket'] ?? '') ?: null)) {
            unhealthy('database unreachable');
        }
        $res = $conn->query("SELECT value FROM $table WHERE name = 'version'");
        $dbversion = $res ? ($res->fetch_row()[0] ?? null) : null;
    }
    if ($dbversion === null) {
        unhealthy('not installed');
    }

    $version = null;
    defined('MOODLE_INTERNAL') || define('MOODLE_INTERNAL', true);
    foreach (['MATURITY_ALPHA' => 50, 'MATURITY_BETA' => 100, 'MATURITY_RC' => 150, 'MATURITY_STABLE' => 200] as $k => $v) {
        defined($k) || define($k, $v);
    }
    include($CFG->dirroot . '/version.php');
    if ($version !== null && (float) $version > (float) $dbversion) {
        unhealthy('upgrade pending');
    }
} catch (Throwable $e) {
    unhealthy('error');
}
echo "OK\n";
