<#
.SYNOPSIS
    Time-phased dunnage MRP: explodes the production schedule
    against the dunnage BOM into daily gross requirements, then
    nets against on-hand inventory (earliest demand consumed first).

.DESCRIPTION
    Demand model per run-day:
        gross bottles/day = speed_bpm x 1440 minutes
        packed bottles    = gross x efficiency
        pallets/day       = packed / glass_per_pallet
        component qty/day = pallets/day x BOM qty_per_pallet

    Results are written back to the database (mrp_daily, mrp_detail)
    so the dashboard and any SQL client can query them.

.PARAMETER AsOfDate
    MRP horizon start. Demand before this date is ignored; runs
    straddling it are clamped (forward-only MRP). Default: today.
#>
[CmdletBinding()]
param(
    [string]$SqlitePath,
    [string]$AsOfDate = (Get-Date -Format 'yyyy-MM-dd')
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

$asOf = [datetime]::ParseExact($AsOfDate, 'yyyy-MM-dd', $null)

# --- pull schedule joined to specs, and the BOM, as JSON ---
$runsJson = & $SqlitePath -json $db @"
SELECT s.run_id, s.line_no, s.item_no, s.load_spec_no, s.start_date, s.end_date,
       s.speed_bpm, s.efficiency, ls.glass_per_pallet
FROM production_schedule s
JOIN load_specs ls ON ls.load_spec_no = s.load_spec_no;
"@
$bomJson = & $SqlitePath -json $db "SELECT load_spec_no, component_id, qty_per_pallet FROM dunnage_bom;"
$ohJson  = & $SqlitePath -json $db "SELECT component_id, qty_on_hand FROM dunnage_on_hand;"

$runs = $runsJson | ConvertFrom-Json
$bom  = $bomJson  | ConvertFrom-Json
$oh   = @{}
foreach ($r in ($ohJson | ConvertFrom-Json)) { $oh[$r.component_id] = [int]$r.qty_on_hand }

# index BOM by load spec
$bomBySpec = @{}
foreach ($b in $bom) {
    if (-not $bomBySpec.ContainsKey($b.load_spec_no)) { $bomBySpec[$b.load_spec_no] = @() }
    $bomBySpec[$b.load_spec_no] += $b
}

# --- explode: day x component gross, plus per-run detail log ---
$gross  = @{}   # "day|component" -> qty
$detail = [System.Collections.Generic.List[string]]::new()

foreach ($run in $runs) {
    $start = [datetime]::ParseExact($run.start_date, 'yyyy-MM-dd', $null)
    $end   = [datetime]::ParseExact($run.end_date,   'yyyy-MM-dd', $null)
    if ($end -lt $asOf) { continue }                 # fully in the past
    if ($start -lt $asOf) { $start = $asOf }         # clamp: forward-only

    $palletsPerDay = ($run.speed_bpm * 1440.0 * $run.efficiency) / $run.glass_per_pallet
    $specBom = $bomBySpec[$run.load_spec_no]
    if (-not $specBom) { continue }

    for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
        $day = $d.ToString('yyyy-MM-dd')
        foreach ($line in $specBom) {
            $qty = [math]::Round($palletsPerDay * $line.qty_per_pallet)
            if ($qty -le 0) { continue }
            $key = "$day|$($line.component_id)"
            if ($gross.ContainsKey($key)) { $gross[$key] += $qty } else { $gross[$key] = $qty }
            $detail.Add("INSERT INTO mrp_detail VALUES ('$day', $($run.line_no), '$($run.item_no)', '$($run.load_spec_no)', '$($line.component_id)', $([math]::Round($palletsPerDay,2)), $($line.qty_per_pallet), $qty);")
        }
    }
}

# --- net: consume on-hand earliest-first per component ---
$remaining = @{}
foreach ($k in $oh.Keys) { $remaining[$k] = $oh[$k] }

$mrpRows = [System.Collections.Generic.List[string]]::new()
foreach ($key in ($gross.Keys | Sort-Object)) {       # sorted = chronological
    $day, $comp = $key -split '\|'
    $g = [int]$gross[$key]
    $avail = if ($remaining.ContainsKey($comp)) { $remaining[$comp] } else { 0 }
    $consumed = [math]::Min($avail, $g)
    if ($remaining.ContainsKey($comp)) { $remaining[$comp] = $avail - $consumed }
    $net = $g - $consumed
    $mrpRows.Add("INSERT INTO mrp_daily VALUES ('$day', '$comp', $g, $net);")
}

# --- write back ---
$sqlFile = Join-Path $env:TEMP 'mrp_load.sql'
@(
    'PRAGMA foreign_keys = ON;'
    'BEGIN;'
    'DELETE FROM mrp_daily;'
    'DELETE FROM mrp_detail;'
    $mrpRows
    $detail
    'COMMIT;'
) | Set-Content $sqlFile -Encoding utf8
& $SqlitePath $db ".read $($sqlFile -replace '\\','/')"
Remove-Item $sqlFile

$summary = & $SqlitePath $db "SELECT COUNT(*), MIN(day), MAX(day), SUM(gross_qty), SUM(net_qty) FROM mrp_daily;"
Write-Host "MRP rebuilt (as of $AsOfDate): rows|first|last|gross|net = $summary"
