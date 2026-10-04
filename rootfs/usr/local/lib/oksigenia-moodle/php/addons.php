<?php
// Lists the add-on (non-standard) plugins found in an existing Moodle code
// tree, and where each one goes in the new tree.
//
// Usage: php addons.php <old-tree> <new-tree>
// Prints "<component>\t<path in old tree>\t<path in new tree>\t<note>" per
// add-on to carry over; the note is "removed" for a plugin that Moodle has
// removed from core. Standard plugins that Moodle has removed from core are
// reported on stderr.
//
// The plugin types and the standard plugin list come from the new tree
// (lib/components.json, lib/plugins.json and each standard plugin's
// db/subplugins.json), so this never runs code from the old tree.

[$old, $new] = [rtrim($argv[1] ?? '', '/'), rtrim($argv[2] ?? '', '/')];
$json = fn(string $f) => json_decode(file_get_contents($f), true, 512, JSON_THROW_ON_ERROR);

$components = $json("$new/lib/components.json");
$plugins = $json("$new/lib/plugins.json");
$newpublic = is_dir("$new/public");
$oldpublic = is_dir("$old/public");
$standard = $plugins['standard'] ?? [];
$deleted = $plugins['deleted'] ?? [];

// Plugin type => directory, relative to the root of the new tree.
$types = ($components['plugintypes'] ?? []) + ($components['deprecatedplugintypes'] ?? []);

// Subplugin types declared by standard plugins (assignsubmission, qbank...).
// Their paths are relative to the web root, which is public/ from 5.1 on.
foreach ($types as $type => $path) {
    foreach ($standard[$type] ?? [] as $name) {
        $file = "$new/$path/$name/db/subplugins.json";
        if (!is_file($file)) {
            continue;
        }
        foreach ($json($file)['plugintypes'] ?? [] as $subtype => $subpath) {
            $types[$subtype] = ($newpublic ? 'public/' : '') . $subpath;
        }
    }
}

$pluginversion = function (string $dir): float {
    $code = @file_get_contents("$dir/version.php");
    return ($code !== false && preg_match('/\$plugin->version\s*=\s*([0-9.]+)/', $code, $m)) ? (float) $m[1] : 0.0;
};

// A plugin that Moodle removed from core is left behind when it is the copy
// that the old Moodle shipped. A separate release of it (moodlehq's Chat and
// Survey, for instance) is an add-on like any other. The old tree tells them
// apart: its Moodle does not list the separate release as standard, or the
// release is newer than that Moodle's core, which no standard plugin is.
$oldstandard = is_file("$old/lib/plugins.json") ? ($json("$old/lib/plugins.json")['standard'] ?? []) : null;
$oldcore = preg_match('/^\$version\s*=\s*([0-9.]+)/m',
    (string) @file_get_contents($oldpublic ? "$old/public/version.php" : "$old/version.php"), $m) ? (float) $m[1] : 0.0;
$shipped = function (string $type, string $name, string $dir) use ($oldstandard, $oldcore, $pluginversion): bool {
    if ($oldstandard !== null && !in_array($name, $oldstandard[$type] ?? [], true)) {
        return false;
    }
    return $oldcore === 0.0 || $pluginversion($dir) <= $oldcore;
};

// The same directory, as laid out in the old tree.
$oldpath = function (string $newrel) use ($newpublic, $oldpublic): string {
    if ($newpublic && !$oldpublic && str_starts_with($newrel, 'public/')) {
        return substr($newrel, strlen('public/'));
    }
    if (!$newpublic && $oldpublic) {
        return "public/$newrel";
    }
    return $newrel;
};

foreach ($types as $type => $newrel) {
    $oldrel = $oldpath($newrel);
    if (!is_dir("$old/$oldrel")) {
        continue;
    }
    foreach (scandir("$old/$oldrel") as $name) {
        if ($name[0] === '.' || !is_file("$old/$oldrel/$name/version.php")) {
            continue;
        }
        if (in_array($name, $standard[$type] ?? [], true)) {
            continue;
        }
        if (is_file("$new/$newrel/$name/version.php")) {
            // The image ships it too (an image built on this one): its copy
            // is used, unless the one in the old tree is newer.
            if ($pluginversion("$old/$oldrel/$name") <= $pluginversion("$new/$newrel/$name")) {
                continue;
            }
        } else if (in_array($name, $deleted[$type] ?? [], true) && $shipped($type, $name, "$old/$oldrel/$name")) {
            fwrite(STDERR, "{$type}_{$name}\n");
            continue;
        }
        $note = in_array($name, $deleted[$type] ?? [], true) ? 'removed' : '';
        echo "{$type}_{$name}\t$oldrel/$name\t$newrel/$name\t$note\n";
    }
}
