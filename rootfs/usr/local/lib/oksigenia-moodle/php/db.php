<?php
// Database checks that run before Moodle can boot.
//
// Usage: php db.php wait|state|activities <module>|theme-usage <theme>
//   wait   retry until the database accepts connections (OKS_DB_WAIT seconds)
//   state  print "installed", "empty" or "partial"
//   activities  number of activities of a module in courses
//   theme-usage  site default, course, category, cohort and user selections of a theme
//
// Connection settings come from the OKS_DB_* environment variables.

function env(string $name, string $default = ''): string {
    $v = getenv($name);
    return ($v === false || $v === '') ? $default : $v;
}

$type = env('OKS_DB_TYPE', 'mariadb');
$prefix = env('OKS_DB_PREFIX', 'mdl_');

function connect(string $type) {
    $host = env('OKS_DB_HOST');
    $port = (int) env('OKS_DB_PORT');
    $name = env('OKS_DB_NAME');
    $user = env('OKS_DB_USER');
    $pass = env('OKS_DB_PASSWORD');
    if ($type === 'pgsql') {
        $dsn = sprintf("host='%s' port=%d dbname='%s' user='%s' password='%s' connect_timeout=5",
            addcslashes($host, "'\\"), $port ?: 5432, addcslashes($name, "'\\"),
            addcslashes($user, "'\\"), addcslashes($pass, "'\\"));
        $conn = @pg_connect($dsn, PGSQL_CONNECT_FORCE_NEW);
        if (!$conn) {
            throw new RuntimeException(error_get_last()['message'] ?? 'connection failed');
        }
        return $conn;
    }
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $conn = mysqli_init();
    $conn->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
    $socket = env('OKS_DB_SOCKET') ?: null;
    $conn->real_connect($host, $user, $pass, $name, $port ?: 3306, $socket);
    return $conn;
}

function query_one($conn, string $type, string $sql) {
    if ($type === 'pgsql') {
        $res = @pg_query($conn, $sql);
        if ($res === false) {
            return null;
        }
        $row = pg_fetch_row($res);
        return $row === false ? null : $row[0];
    }
    try {
        $row = $conn->query($sql)->fetch_row();
    } catch (mysqli_sql_exception $e) {
        return null;
    }
    return $row === null ? null : $row[0];
}

$action = $argv[1] ?? '';

if ($action === 'wait') {
    $deadline = time() + (int) env('OKS_DB_WAIT', '300');
    $last = '';
    while (true) {
        try {
            connect($type);
            exit(0);
        } catch (Throwable $e) {
            $msg = $e->getMessage();
            if ($msg !== $last) {
                fwrite(STDERR, "[moodle] waiting for the database: $msg\n");
                $last = $msg;
            }
            if (time() >= $deadline) {
                fwrite(STDERR, "[moodle] ERROR: the database is not reachable\n");
                exit(1);
            }
            sleep(3);
        }
    }
}

if ($action === 'state') {
    $conn = connect($type);
    $table = $prefix . 'config';
    if ($type === 'pgsql') {
        $exists = query_one($conn, $type, "SELECT to_regclass('" . pg_escape_string($conn, $table) . "') IS NOT NULL") === 't';
    } else {
        $exists = query_one($conn, $type, "SHOW TABLES LIKE '" . $conn->real_escape_string($table) . "'") !== null;
    }
    if (!$exists) {
        // Other Moodle tables without the config table: a failed install.
        $other = $type === 'pgsql'
            ? query_one($conn, $type, "SELECT count(*) FROM pg_tables WHERE tablename LIKE '" . pg_escape_string($conn, $prefix) . "%'")
            : query_one($conn, $type, "SELECT count(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE '" . $conn->real_escape_string($prefix) . "%'");
        echo ((int) $other > 0 ? 'partial' : 'empty'), "\n";
        exit(0);
    }
    $version = query_one($conn, $type, "SELECT value FROM $table WHERE name = 'version'");
    echo ($version === null ? 'partial' : 'installed'), "\n";
    exit(0);
}

// Number of activities of a module (e.g. "chat") in courses, 0 if none.
if ($action === 'activities') {
    $conn = connect($type);
    $module = preg_replace('/[^a-z0-9_]/', '', $argv[2] ?? '');
    $n = query_one($conn, $type, "SELECT COUNT(*) FROM {$prefix}course_modules cm
        JOIN {$prefix}modules m ON m.id = cm.module WHERE m.name = '$module'");
    echo (int) $n, "\n";
    exit(0);
}

// How much a theme is in use: the site default, plus course, category,
// cohort and user selections where the site allows them (otherwise those
// values are ignored by Moodle and do not count).
if ($action === 'theme-usage') {
    $conn = connect($type);
    $theme = preg_replace('/[^a-z0-9_]/', '', $argv[2] ?? '');
    $config = fn(string $name) => query_one($conn, $type, "SELECT value FROM {$prefix}config WHERE name = '$name'");
    $n = ($config('theme') === $theme) ? 1 : 0;
    $tables = ['course' => 'allowcoursethemes', 'course_categories' => 'allowcategorythemes',
        'cohort' => 'allowcohortthemes', 'user' => 'allowuserthemes'];
    foreach ($tables as $table => $setting) {
        if (!empty($config($setting))) {
            $n += (int) query_one($conn, $type, "SELECT COUNT(*) FROM {$prefix}{$table} WHERE theme = '$theme'");
        }
    }
    echo $n, "\n";
    exit(0);
}

// Remove a core setting, e.g. the upgraderunning flag that a failed upgrade
// leaves behind (Moodle refuses most scripts while it is in the future).
if ($action === 'unset-config') {
    $conn = connect($type);
    $name = preg_replace('/[^a-z0-9_]/', '', $argv[2] ?? '');
    $sql = "DELETE FROM {$prefix}config WHERE name = '$name'";
    $type === 'pgsql' ? pg_query($conn, $sql) : $conn->query($sql);
    exit(0);
}

fwrite(STDERR, "usage: db.php wait|state|activities <module>|theme-usage <theme>|unset-config <name>\n");
exit(2);
