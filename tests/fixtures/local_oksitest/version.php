<?php
// Minimal plugin used by the tests to check that add-ons survive upgrades
// and migrations.
defined('MOODLE_INTERNAL') || die();

$plugin->component = 'local_oksitest';
$plugin->version = 2026100300;
$plugin->requires = 2024100700;
$plugin->maturity = MATURITY_STABLE;
$plugin->release = '1.0';
