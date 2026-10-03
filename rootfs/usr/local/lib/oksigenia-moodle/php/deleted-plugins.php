<?php
// Lists the standard plugins that Moodle removed from core, that are still
// registered (status "delete") and that hold nothing: blocks without
// instances and activity modules without activities. Other plugin types are
// left alone; Moodle's plugin overview shows them.
//
// Usage: php deleted-plugins.php <code-dir>
// Prints a comma-separated list of components, or nothing.

define('CLI_SCRIPT', true);
require(rtrim($argv[1], '/') . '/config.php');

global $DB;
$unused = [];
foreach (core_plugin_manager::instance()->get_plugins() as $type => $plugins) {
    foreach ($plugins as $name => $plugin) {
        if ($plugin->get_status() !== core_plugin_manager::PLUGIN_STATUS_DELETE) {
            continue;
        }
        if ($type === 'block') {
            $inuse = $DB->count_records('block_instances', ['blockname' => $name]);
        } else if ($type === 'mod') {
            $module = $DB->get_record('modules', ['name' => $name]);
            $inuse = $module ? $DB->count_records('course_modules', ['module' => $module->id]) : 0;
        } else {
            continue;
        }
        if ($inuse === 0) {
            $unused[] = "{$type}_{$name}";
        }
    }
}
echo implode(',', $unused);
