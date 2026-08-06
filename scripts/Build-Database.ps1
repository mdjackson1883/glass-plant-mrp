<#
.SYNOPSIS
    Rebuilds bluegrass.db from sql\schema.sql + sql\seed_data.sql.

.DESCRIPTION
    Always rebuilds from scratch (drop-and-recreate) so the database
    is a pure function of the committed SQL — no drift, no doubling.
    Locates sqlite3.exe on PATH or via -SqlitePath.
#>
[CmdletBinding()]
param(
    [string]$SqlitePath
)

$root = Split-Path $PSScriptRoot -Parent
$db   = Join-Path $root 'bluegrass.db'

# --- locate sqlite3 ---
if (-not $SqlitePath) {
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { $SqlitePath = $cmd.Source }
}
if (-not $SqlitePath -or -not (Test-Path $SqlitePath)) {
    throw "sqlite3.exe not found. Install SQLite (winget install SQLite.SQLite) or pass -SqlitePath."
}

# --- rebuild from scratch ---
if (Test-Path $db) { Remove-Item $db -Force }
& $SqlitePath $db ".read $(Join-Path $root 'sql\schema.sql' -Resolve | ForEach-Object { $_ -replace '\\','/' })"
& $SqlitePath $db ".read $((Join-Path $root 'sql\seed_data.sql' -Resolve) -replace '\\','/')"

# --- validate ---
$counts = & $SqlitePath $db "SELECT 'customers', COUNT(*) FROM customers UNION ALL SELECT 'items', COUNT(*) FROM items UNION ALL SELECT 'load_specs', COUNT(*) FROM load_specs UNION ALL SELECT 'dunnage_bom', COUNT(*) FROM dunnage_bom UNION ALL SELECT 'schedule_runs', COUNT(*) FROM production_schedule;"
$fk = & $SqlitePath $db "PRAGMA foreign_key_check;"
if ($fk) { throw "Foreign key violations found:`n$fk" }

Write-Host "Database rebuilt: $db"
$counts | ForEach-Object { Write-Host "  $_" }
Write-Host "  FK check: clean"
