<?php
// Lists the add-on (non-standard) plugins found in an existing Moodle code
// tree, and where each one goes in the new tree.
//
// Usage: php addons.php <old-tree> <new-tree>
// Prints "<component>\t<path in old tree>\t<path in new tree>" per add-on.
// Standard plugins that Moodle has removed from core are reported on stderr.
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
        if (in_array($name, $deleted[$type] ?? [], true)) {
            fwrite(STDERR, "{$type}_{$name}\n");
            continue;
        }
        echo "{$type}_{$name}\t$oldrel/$name\t$newrel/$name\n";
    }
}
