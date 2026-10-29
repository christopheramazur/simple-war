$root = (Get-Location).Path
Write-Output "ROOT: $root"
Write-Output "--- GDD top dirs ---"
Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -like 'Game*' } | ForEach-Object {
    Write-Output ("DIR: '" + $_.Name + "'")
    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
        Write-Output ("  SUBDIR: '" + $_.Name + "'")
    }
    Get-ChildItem -Path $_.FullName | ForEach-Object {
        Write-Output ("  FILE: '" + $_.Name + "'")
    }
}
Write-Output "--- Foundation subdirs/files (deep) ---"
$found = Get-ChildItem -Path $root -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*Foundation*' }
foreach ($f in $found) {
    Write-Output ("FND: '" + $f.FullName + "'")
    Get-ChildItem -Path $f.FullName -File | ForEach-Object {
        Write-Output ("  '" + $_.Name + "'")
    }
}
