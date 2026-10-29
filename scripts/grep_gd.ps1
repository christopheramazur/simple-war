param(
    [Parameter(Mandatory=$true)][string]$Pattern,
    [Parameter(Mandatory=$true)][string]$Path
)
$lines = Get-Content -Path $Path
$i = 0
foreach ($line in $lines) {
    $i++
    if ($line -match $Pattern) {
        Write-Output ("{0} -> {1}" -f $i, $line)
    }
}
