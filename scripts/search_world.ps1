$root = 'C:\Users\chris\Documents\simple-war'
$file = Join-Path $root 'addons\gecs\ecs\world.gd'
$i = 0
foreach ($line in Get-Content -Path $file) {
    $i++
    if ($line -like 'func add_entity*' -or $line -like 'func process*' -or $line -like 'func add_system*' -or $line -like 'func remove_entity*' -or $line -like 'func flush_command_buffers*' -or $line -like 'func finalize_system_setup*') {
        Write-Output ("{0}|{1}" -f $i, $line)
    }
}
