<?php
// Compares the Moodle code in a volume with the code shipped in the image.
//
// Usage: php code-state.php <volume-dir> <image-dir>
// Prints one line, "<state> <details>", where state is one of:
//   fresh        the volume has no Moodle code yet
//   same         same version, nothing to do
//   upgrade      the image is newer; the code must be replaced
//   downgrade    the volume is newer than the image (refuse to start)
//   unsupported  Moodle cannot upgrade directly from the volume's version

function tree_info(string $dir): ?array {
    foreach (['public/version.php', 'version.php'] as $rel) {
        $file = "$dir/$rel";
        if (is_file($file)) {
            return read_version($file) + ['public' => str_starts_with($rel, 'public/')];
        }
    }
    return null;
}

function read_version(string $file): array {
    defined('MOODLE_INTERNAL') || define('MOODLE_INTERNAL', true);
    foreach (['MATURITY_ALPHA' => 50, 'MATURITY_BETA' => 100, 'MATURITY_RC' => 150, 'MATURITY_STABLE' => 200] as $k => $v) {
        defined($k) || define($k, $v);
    }
    $version = $release = $branch = null;
    include $file;
    return ['version' => (string) $version, 'release' => (string) $release, 'branch' => (string) $branch];
}

// "5.2.3+ (Build: 20260914)" -> "5.2"
function major_minor(string $release): string {
    return preg_match('/^(\d+)\.(\d+)/', $release, $m) ? "$m[1].$m[2]" : '';
}

// Minimum version Moodle accepts as a starting point for an upgrade,
// from the image's own environment.xml.
function upgrade_requires(string $dir, string $target): ?string {
    foreach (["$dir/public/admin/environment.xml", "$dir/admin/environment.xml"] as $file) {
        if (!is_file($file)) {
            continue;
        }
        $xml = simplexml_load_file($file);
        foreach ($xml->MOODLE as $section) {
            if ((string) $section['version'] === $target) {
                return (string) $section['requires'] ?: null;
            }
        }
    }
    return null;
}

[$volume, $image] = [$argv[1] ?? '', $argv[2] ?? ''];
$new = tree_info($image) ?? exit("error image has no version.php\n");
$old = tree_info($volume);

if ($old === null) {
    echo "fresh {$new['release']}\n";
    exit(0);
}
$cmp = bccomp_versions($old['version'], $new['version']);
// A new branch can start at the version of the previous branch's last
// release: main as 6.0dev and 5.3.0 are both 2026100500.00 at first.
if ($cmp === 0) {
    $cmp = (int) $old['branch'] <=> (int) $new['branch'];
}
if ($cmp === 0) {
    echo "same {$old['release']}\n";
} else if ($cmp > 0) {
    echo "downgrade {$old['release']} > {$new['release']}\n";
} else {
    $requires = upgrade_requires($image, major_minor($new['release']));
    if ($requires !== null && version_compare(major_minor($old['release']), $requires, '<')) {
        echo "unsupported {$old['release']} -> {$new['release']} (Moodle needs {$requires} or later first)\n";
    } else {
        echo "upgrade {$old['release']} -> {$new['release']}\n";
    }
}

// Moodle versions look like 2026042003.02; compare them as decimals.
function bccomp_versions(string $a, string $b): int {
    [$ai, $af] = array_pad(explode('.', $a, 2), 2, '0');
    [$bi, $bf] = array_pad(explode('.', $b, 2), 2, '0');
    if ($ai !== $bi) {
        return (int) $ai <=> (int) $bi;
    }
    return strcmp(str_pad($af, 4, '0'), str_pad($bf, 4, '0')) <=> 0;
}
