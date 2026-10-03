<?php
// Plugin whose install always fails, to test what happens after a failed upgrade.
defined('MOODLE_INTERNAL') || die();

$plugin->component = 'local_oksifail';
$plugin->version = 2026100300;
$plugin->requires = 2024100700;
$plugin->maturity = MATURITY_STABLE;
