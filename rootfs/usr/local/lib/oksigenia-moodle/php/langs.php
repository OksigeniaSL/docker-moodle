<?php
// Installs or updates Moodle language packs from download.moodle.org.
//
// Usage: php langs.php <code-dir> es,ca,eu

define('CLI_SCRIPT', true);
require(rtrim($argv[1], '/') . '/config.php');
require_once($CFG->libdir . '/clilib.php');

$langs = array_values(array_filter(array_map('trim', explode(',', $argv[2] ?? ''))));
$langs = array_filter($langs, fn($l) => $l !== 'en' && clean_param($l, PARAM_SAFEDIR) === $l);
if (!$langs) {
    exit(0);
}

// Language packs are downloaded into dataroot/lang.
\core\session\manager::set_user(get_admin());
$controller = new \tool_langimport\controller();
try {
    $controller->install_languagepacks($langs);
} catch (Throwable $e) {
    cli_problem('Language packs: ' . $e->getMessage());
    exit(1);
}
foreach ($controller->info as $msg) {
    mtrace('[moodle] ' . strip_tags($msg));
}
foreach ($controller->errors as $msg) {
    cli_problem('[moodle] ' . strip_tags($msg));
}
exit($controller->errors ? 1 : 0);
