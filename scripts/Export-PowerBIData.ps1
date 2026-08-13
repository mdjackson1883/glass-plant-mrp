<#
.SYNOPSIS
    Exports every table in bluegrass.db to powerbi\data\*.csv for
    Power BI Desktop (Get data -> Text/CSV).

.DESCRIPTION
    Writes header rows, UTF-8 without BOM, and no blank lines between
    records. Power BI reads column names from the header row, so an
    export without one silently imports every field as Column1,
    Column2, ... and the first data row is lost.

    Row order is pinned by primary key so re-running produces a clean
    diff instead of a reshuffled file.
#>
[CmdletBinding()]
param(
    [string]$SqlitePath
)

$root = Split-Path $PSScriptRoot -Parent
$db   = Join-Path $root 'bluegrass.db'
if (-not (Test-Path $db)) { throw "bluegrass.db not found - run Build-Database.ps1 first." }

if (-not $SqlitePath) {
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { $SqlitePath = $cmd.Source }
}
if (-not $SqlitePath -or -not (Test-Path $SqlitePath)) {
    throw "sqlite3.exe not found. Install SQLite or pass -SqlitePath."
}

# table -> ORDER BY clause (primary key, so exports are reproducible)
$tables = [ordered]@{
    'customers'           = 'customer_id'
    'items'               = 'item_no'
    'load_specs'          = 'load_spec_no'
    'dunnage_components'  = 'component_id'
    'dunnage_bom'         = 'load_spec_no, component_id'
    'production_lines'    = 'line_no'
    'production_schedule' = 'run_id'
    'dunnage_on_hand'     = 'component_id'
    'mrp_daily'           = 'day, component_id'
    'mrp_detail'          = 'day, line_no, item_no, component_id'
}

$outDir = Join-Path $root 'powerbi\data'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# Out-File/Set-Content would re-terminate each line and leave a blank
# row between records; WriteAllLines writes exactly one CRLF per line.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($table in $tables.Keys) {
    $sql = "SELECT * FROM $table ORDER BY $($tables[$table]);"

    # Flag order matters: '-header -csv' silently emits NO header,
    # because -csv resets the header setting.
    $lines = @(& $SqlitePath -csv -header $db $sql | Where-Object { $_.Trim() -ne '' })

    if ($lines.Count -lt 2) { throw "$table exported no rows - is the database populated?" }

    $expected = (& $SqlitePath $db "PRAGMA table_info($table);" |
                 ForEach-Object { ($_ -split '\|')[1] }) -join ','
    if ($lines[0] -ne $expected) {
        throw "$table header mismatch - got '$($lines[0])', expected '$expected'."
    }

    $path = Join-Path $outDir "$table.csv"
    [System.IO.File]::WriteAllLines($path, $lines, $utf8NoBom)
    Write-Host ("  {0,-22} {1,5} rows" -f $table, ($lines.Count - 1))
}

Write-Host "Power BI CSVs written: $outDir"
