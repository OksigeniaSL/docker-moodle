<?php
// Finds add-on activity modules that Moodle 5.3 and later refuse to upgrade
// ("detectedbrokenplugin"): their <mod>_supports() still answers true to
// FEATURE_GROUPMEMBERSONLY. Static check of lib.php, so no plugin code runs.
//
// Usage: php broken-addons.php <old-tree> <component>=<path in old tree> ...
// Prints "<component>\t<file>" for each offending module.

$old = rtrim($argv[1] ?? '', '/');
foreach (array_slice($argv, 2) as $arg) {
    [$component, $path] = explode('=', $arg, 2) + [1 => ''];
    if (!str_starts_with($component, 'mod_')) {
        continue;
    }
    $file = "$old/$path/lib.php";
    $src = @file_get_contents($file);
    if ($src === false) {
        continue;
    }
    // case FEATURE_GROUPMEMBERSONLY: [case ...:] return true;   or   FEATURE_GROUPMEMBERSONLY => true
    if (preg_match('/case\s+FEATURE_GROUPMEMBERSONLY\s*:\s*(?:case\s+[A-Z_]+\s*:\s*)*return\s+true\s*;/i', $src)
            || preg_match('/FEATURE_GROUPMEMBERSONLY\s*(?:,\s*FEATURE_[A-Z_]+\s*)*=>\s*true/i', $src)) {
        echo "$component\t$path/lib.php\n";
    }
}
