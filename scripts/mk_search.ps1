$root = 'C:\Users\chris\Documents\simple-war'
$out = Join-Path $root 'scripts\_out.txt'
$jobs = @()
$jobs += @('system.gd', [regex]'^\s*class_name\s|func add_entity|func process|func query|func setup|func _ready|cmd|property.*flush|flush_command_buffer')