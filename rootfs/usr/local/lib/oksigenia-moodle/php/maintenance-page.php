<?php
// Fills the maintenance page in with this site's name, logo and brand colour, and leaves it where Moodle's CLI
// maintenance mode looks for a template. A template the site put there itself stays: the hash of what this script
// wrote tells them apart. A maintenance message set in the site goes first in Moodle, over any template.
//
// Usage: php maintenance-page.php <code-dir> <state-dir> <page>

define('CLI_SCRIPT', true);
require(rtrim($argv[1], '/') . '/config.php');

global $CFG, $SITE;

$target = $CFG->dataroot . '/climaintenance.template.html';
$record = $argv[2] . '/maintenance-page.sha256';
$written = is_file($record) ? trim(file_get_contents($record)) : '';
if (file_exists($target) && hash_file('sha256', $target) !== $written) {
    exit(0);
}

$theme = 'theme_' . ($CFG->theme ?? 'boost');
$context = context_system::instance();

// The colour only paints the book's covers and the focus ring. On the dark page, a lighter one, or it would not show.
$accent = '#17574c';
$accentdark = '#4fae98';
$brand = preg_replace('/^#([0-9a-f])([0-9a-f])([0-9a-f])$/i', '#$1$1$2$2$3$3', trim((string) get_config($theme, 'brandcolor')));
if (preg_match('/^#[0-9a-f]{6}$/i', $brand)) {
    $accent = $brand;
    $accentdark = '#' . implode('', array_map(
        fn($c) => sprintf('%02x', round(hexdec($c) + (255 - hexdec($c)) * 0.45)),
        str_split(substr($brand, 1), 2)
    ));
}

// The logo goes inside the page, because Moodle is not there to serve it. 112 px is twice the height the page shows.
$logo = '';
foreach ([$theme, 'core_admin'] as $component) {
    $files = get_file_storage()->get_area_files($context->id, $component, 'logo', 0, 'filename', false);
    $file = reset($files);
    if (!$file) {
        continue;
    }
    $svg = $file->get_mimetype() === 'image/svg+xml';
    $data = $svg ? $file->get_content() : $file->resize_image(null, 112);
    if ($data && strlen($data) <= 256 * 1024) {
        $logo = '<img src="data:image/' . ($svg ? 'svg+xml' : 'png') . ';base64,' . base64_encode($data) . '" alt="">';
    }
    break;
}

$page = strtr(file_get_contents($argv[3]), [
    '{{SITE_NAME}}' => strip_tags(format_string($SITE->fullname, true, ['context' => $context])),
    '{{LOGO}}' => $logo,
    '{{ACCENT}}' => $accent,
    '{{ACCENT_DARK}}' => $accentdark,
    '{{LANG}}' => str_replace('_', '-', $CFG->lang ?? 'en'),
]);

$hash = hash('sha256', $page);
if ($hash !== $written || !file_exists($target)) {
    file_put_contents($target . '.tmp', $page);
    chmod($target . '.tmp', $CFG->filepermissions);
    rename($target . '.tmp', $target);
    file_put_contents($record, $hash . "\n");
}
