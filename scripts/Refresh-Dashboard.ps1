<#
.SYNOPSIS
    Regenerates dashboard\Dashboard.html from bluegrass.db by
    embedding query results as JSON into dashboard\template.html.

.DESCRIPTION
    The output is a single self-contained offline HTML file —
    no server, no dependencies. Open it in any browser.
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

function Query([string]$sql) {
    $json = & $SqlitePath -json $db $sql
    if ($json) { ,($json | ConvertFrom-Json) } else { ,@() }
}

$items = Query @"
SELECT i.item_no AS no, i.description AS desc, c.customer_name AS customer,
       c.market, i.capacity_ml AS ml, i.weight_oz AS wt
FROM items i JOIN customers c ON c.customer_id = i.customer_id
ORDER BY i.item_no;
"@

$loadSpecs = Query @"
SELECT load_spec_no AS no, item_no AS item, pack_type AS pack,
       pallet_footprint AS fp, layers, glass_per_pallet AS gpp
FROM load_specs ORDER BY load_spec_no;
"@

$bom = Query @"
SELECT b.load_spec_no AS spec, b.component_id AS comp, dc.description AS desc,
       dc.category AS cat, b.qty_per_pallet AS qty
FROM dunnage_bom b JOIN dunnage_components dc ON dc.component_id = b.component_id
ORDER BY b.load_spec_no, dc.category;
"@

$components = Query @"
SELECT dc.component_id AS id, dc.description AS desc, dc.item_number AS itemno,
       COALESCE(oh.qty_on_hand, 0) AS onhand
FROM dunnage_components dc
LEFT JOIN dunnage_on_hand oh ON oh.component_id = dc.component_id
ORDER BY dc.component_id;
"@

$runs = Query @"
SELECT s.run_id AS id, s.line_no AS line, s.item_no AS item, ls.pack_type AS pack,
       s.start_date AS start, s.end_date AS end,
       CAST(julianday(s.end_date) - julianday(s.start_date) + 1 AS INTEGER) AS days,
       s.speed_bpm AS speed, s.efficiency AS eff,
       (s.speed_bpm * 1440.0 * s.efficiency) / ls.glass_per_pallet AS ppd
FROM production_schedule s
JOIN load_specs ls ON ls.load_spec_no = s.load_spec_no
ORDER BY s.line_no, s.start_date;
"@

$mrp = Query "SELECT day, component_id AS comp, gross_qty AS gross, net_qty AS net FROM mrp_daily ORDER BY day, component_id;"

$data = [ordered]@{
    generated  = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    items      = @($items)
    loadSpecs  = @($loadSpecs)
    bom        = @($bom)
    components = @($components)
    runs       = @($runs)
    mrp        = @($mrp)
} | ConvertTo-Json -Depth 5 -Compress

$template = Get-Content (Join-Path $root 'dashboard\template.html') -Raw
$outHtml  = $template -replace '/\*__DATA__\*/\{\}/\*__END__\*/', "/*__DATA__*/$data/*__END__*/"
Set-Content (Join-Path $root 'dashboard\Dashboard.html') $outHtml -Encoding utf8

Write-Host "Dashboard written: $(Join-Path $root 'dashboard\Dashboard.html')"
Write-Host "  items=$($items.Count) specs=$($loadSpecs.Count) bom=$($bom.Count) runs=$($runs.Count) mrpRows=$($mrp.Count)"
