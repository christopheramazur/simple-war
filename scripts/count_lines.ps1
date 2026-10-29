$root = 'C:\Users\chris\Documents\simple-war'
$rel = @('addons\gecs\ecs\world.gd','addons\gecs\ecs\system.gd','addons\gecs\lib\system_group.gd','addons\gecs\ecs\entity.gd','addons\gecs\ecs\component.gd','addons\gecs\ecs\command_buffer.gd','addons\gecs\ecs\query_builder.gd')
foreach ($r in $rel) {
    $full = Join-Path $root $r
    $count = (Get-Content -Path $full).Count
    Write-Output ("$r : $count lines")
}
