<?php
// Points Moodle's application cache (MUC) at Redis. Sessions use Redis
// through config.php; this adds a Redis cache store and makes it the
// default for application caches. Idempotent: it updates the store if the
// connection settings change.
//
// Usage: php redis-cache.php <code-dir>          (set up or update)
//        php redis-cache.php <code-dir> remove   (back to Moodle's default store)
// Reads MOODLE_REDIS_HOST, MOODLE_REDIS_PORT and MOODLE_REDIS_PASSWORD.

define('CLI_SCRIPT', true);
require(rtrim($argv[1], '/') . '/config.php');
require_once($CFG->libdir . '/clilib.php');
if (file_exists($CFG->dirroot . '/cache/locallib.php')) {
    require_once($CFG->dirroot . '/cache/locallib.php');
}

$name = 'oksigenia_redis';
$writer = cache_config_writer::instance();

if (($argv[2] ?? '') === 'remove') {
    $writer->set_mode_mappings([
        cache_store::MODE_APPLICATION => ['default_application'],
        cache_store::MODE_SESSION => ['default_session'],
        cache_store::MODE_REQUEST => ['default_request'],
    ]);
    if (isset($writer->get_all_stores()[$name])) {
        try {
            $writer->delete_store_instance($name);
        } catch (Throwable $e) {
            // Still mapped to some cache definition by hand: leave the store.
            mtrace("[moodle] the Redis cache store stays defined: " . $e->getMessage());
        }
    }
    mtrace("[moodle] application cache back on Moodle's default store (MOODLE_REDIS_HOST is not set)");
    exit(0);
}

$host = getenv('MOODLE_REDIS_HOST');
$port = getenv('MOODLE_REDIS_PORT') ?: '6379';
$config = [
    'server' => "$host:$port",
    'prefix' => 'mdl_muc_',
    'password' => (string) getenv('MOODLE_REDIS_PASSWORD'),
    'serializer' => defined('Redis::SERIALIZER_IGBINARY') ? Redis::SERIALIZER_IGBINARY : Redis::SERIALIZER_PHP,
    'compressor' => 0,
    'connectiontimeout' => 3,
    'readtimeout' => 3,
    'encryption' => false,
    'cafile' => '',
    'clustermode' => false,
];

$stores = $writer->get_all_stores();
if (isset($stores[$name])) {
    $writer->edit_store_instance($name, 'redis', $config);
} else {
    $writer->add_store_instance($name, 'redis', $config);
}
$writer->set_mode_mappings([
    cache_store::MODE_APPLICATION => [$name],
    cache_store::MODE_SESSION => ['default_session'],
    cache_store::MODE_REQUEST => ['default_request'],
]);
mtrace("[moodle] application cache stored in Redis at $host:$port");
