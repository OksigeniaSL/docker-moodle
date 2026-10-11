<?php
// Minimal plugin used by the tests to check that add-ons survive upgrades
// and migrations.
defined('MOODLE_INTERNAL') || die();

$plugin->component = 'local_oksitest';
$plugin->version = 2026100300;
$plugin->requires = 2022112800; // 4.1: the oldest Bitnami release the 4.5 image upgrades
$plugin->maturity = MATURITY_STABLE;
$plugin->release = '1.0';
