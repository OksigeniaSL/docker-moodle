<?php
// Reads the database settings from an existing config.php (for instance one
// written by bitnami/moodle) without booting Moodle: the require of
// lib/setup.php is stripped before the file is evaluated.
//
// Usage: php read-config.php <config.php>
// Prints shell assignments (OKS_DB_TYPE=...) quoted for eval.

$file = $argv[1] ?? '';
$src = @file_get_contents($file);
if ($src === false) {
    fwrite(STDERR, "cannot read $file\n");
    exit(1);
}
$src = preg_replace('/^\s*require(_once)?\s*\(?\s*__DIR__\s*\.\s*[\'"]\/lib\/setup\.php[\'"]\s*\)?\s*;/m', '', $src);
$src = preg_replace('/^\s*require(_once)?\s*\(?\s*dirname\(__FILE__\)\s*\.\s*[\'"]\/lib\/setup\.php[\'"]\s*\)?\s*;/m', '', $src);

$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
$tmp = tempnam(sys_get_temp_dir(), 'cfg');
file_put_contents($tmp, $src);
(function () use ($tmp) {
    global $CFG;
    include $tmp;
})();
unlink($tmp);

global $CFG;
$out = [
    'OKS_DB_TYPE' => $CFG->dbtype ?? '',
    'OKS_DB_HOST' => $CFG->dbhost ?? '',
    'OKS_DB_PORT' => (string) ($CFG->dboptions['dbport'] ?? ''),
    'OKS_DB_SOCKET' => (string) ($CFG->dboptions['dbsocket'] ?? ''),
    'OKS_DB_NAME' => $CFG->dbname ?? '',
    'OKS_DB_USER' => $CFG->dbuser ?? '',
    'OKS_DB_PASSWORD' => $CFG->dbpass ?? '',
    'OKS_DB_PREFIX' => $CFG->prefix ?? 'mdl_',
    'OKS_CFG_DATAROOT' => $CFG->dataroot ?? '',
    'OKS_CFG_WWWROOT' => $CFG->wwwroot ?? '',
];
foreach ($out as $k => $v) {
    echo $k, '=', escapeshellarg((string) $v), "\n";
}
