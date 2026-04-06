param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$Category = ""  # 为空则统计全部；填 rag 则只统计该分类
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$rows = Import-Csv -LiteralPath $CsvPath -Encoding UTF8
if ($null -eq $rows -or @($rows).Count -eq 0) {
    throw "CSV is empty: $CsvPath"
}

function Parse-Pass {
    param([string]$v)
    if ($null -eq $v) { return $false }
    $s = $v.ToString().Trim()
    return ($s -eq "True" -or $s -eq "true" -or $s -eq "1")
}

$filtered = @($rows)
if ($Category -ne "") {
    $filtered = @($rows | Where-Object { $_.category -eq $Category })
}

if ($filtered.Count -eq 0) {
    Write-Host "No rows for category filter: '$Category'"
    exit 0
}

$passCount = 0
$sumMust = 0
$sumHit = 0
foreach ($r in $filtered) {
    if (Parse-Pass $r.pass) { $passCount++ }
    $mt = 0
    $mh = 0
    [void][int]::TryParse([string]$r.must_total, [ref]$mt)
    [void][int]::TryParse([string]$r.must_hit, [ref]$mh)
    $sumMust += $mt
    $sumHit += $mh
}

$n = $filtered.Count
$rate = if ($n -gt 0) { [Math]::Round(100.0 * $passCount / $n, 2) } else { 0 }
$keywordScore = if ($sumMust -gt 0) { [Math]::Round(100.0 * $sumHit / $sumMust, 2) } else { 0 }

Write-Host ""
Write-Host "========== EVAL SUMMARY =========="
Write-Host "CSV file     : $CsvPath"
if ($Category -ne "") {
    Write-Host "Filter       : category = $Category"
} else {
    Write-Host "Filter       : (all rows)"
}
Write-Host "Rows         : $n"
Write-Host "Pass count   : $passCount"
Write-Host "Pass rate    : $rate %"
Write-Host "Keyword hits : $sumHit / $sumMust"
Write-Host "Keyword score: $keywordScore %  (must_hit / must_total)"
Write-Host "=================================="
Write-Host ""

# By category (only when not filtering)
if ($Category -eq "") {
    Write-Host "---- By category ----"
    $groups = $rows | Group-Object category | Sort-Object Name
    foreach ($g in $groups) {
        $gc = $g.Count
        $gp = 0
        foreach ($row in $g.Group) {
            if (Parse-Pass $row.pass) { $gp++ }
        }
        $gr = if ($gc -gt 0) { [Math]::Round(100.0 * $gp / $gc, 2) } else { 0 }
        Write-Host ("{0,-12} pass {1}/{2}  ({3}%)" -f $g.Name, $gp, $gc, $gr)
    }
    Write-Host ""
}

# Failed ids (unique)
$failed = @($filtered | Where-Object { -not (Parse-Pass $_.pass) } | ForEach-Object { $_.id } | Sort-Object -Unique)
if ($failed.Count -gt 0) {
    Write-Host "Failed ids: $($failed -join ', ')"
} else {
    Write-Host "Failed ids: (none)"
}
Write-Host ""
