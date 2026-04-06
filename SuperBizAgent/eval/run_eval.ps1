param(
    [string]$BaseUrl = "http://localhost:9900",
    [string]$DatasetPath = ".\chunk_topk_testset.jsonl",
    [string]$OutCsv = ".\last_eval_result.csv",
    [int]$Repeat = 1,
    [string]$SessionPrefix = "eval"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve paths from the script folder (works with -File; PSScriptRoot is most reliable).
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Run with: powershell -File `"$PSCommandPath`""
}
if (-not [System.IO.Path]::IsPathRooted($DatasetPath)) {
    $DatasetPath = Join-Path $scriptDir $DatasetPath
}
if (-not [System.IO.Path]::IsPathRooted($OutCsv)) {
    $OutCsv = Join-Path $scriptDir $OutCsv
}
$outDir = Split-Path -Parent $OutCsv
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

function Read-Jsonl {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Dataset not found: $Path"
    }
    $items = @()
    Get-Content -Path $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -ne "") {
            $items += ($line | ConvertFrom-Json)
        }
    }
    # Always return an array (single-line jsonl would otherwise be one object and break foreach)
    return @($items)
}

function Invoke-Chat {
    param(
        [string]$Url,
        [string]$SessionId,
        [string]$Question
    )
    $body = @{
        Id = $SessionId
        Question = $Question
    } | ConvertTo-Json

    $resp = Invoke-RestMethod -Method Post -Uri "$Url/api/chat" -ContentType "application/json; charset=utf-8" -Body $body
    if ($null -eq $resp) { return "" }

    if ($resp.PSObject.Properties.Name -contains "data") {
        if ($resp.data -and ($resp.data.PSObject.Properties.Name -contains "answer")) {
            return [string]$resp.data.answer
        }
    }
    return ($resp | ConvertTo-Json -Depth 8)
}

function Test-Keywords {
    param(
        [string]$Answer,
        [object[]]$MustKeywords
    )
    if ($null -eq $MustKeywords -or $MustKeywords.Count -eq 0) {
        return @{
            MustTotal = 0
            MustHit = 0
            Pass = $true
            Missing = ""
        }
    }

    $missing = @()
    $hit = 0
    foreach ($kw in $MustKeywords) {
        $s = [string]$kw
        if ($Answer -like "*$s*") {
            $hit++
        } else {
            $missing += $s
        }
    }

    return @{
        MustTotal = $MustKeywords.Count
        MustHit = $hit
        Pass = ($missing.Count -eq 0)
        Missing = ($missing -join "|")
    }
}

Write-Host "Script dir  : $scriptDir"
Write-Host "Dataset     : $DatasetPath"
Write-Host "Out CSV     : $OutCsv"
Write-Host ""

$cases = Read-Jsonl -Path $DatasetPath
if (@($cases).Count -eq 0) {
    throw "Dataset is empty: $DatasetPath"
}

$rows = @()
$totalRuns = $cases.Count * $Repeat
$counter = 0

for ($r = 1; $r -le $Repeat; $r++) {
    foreach ($c in $cases) {
        $counter++
        $sessionId = "$SessionPrefix-$($c.id)-r$r"
        $question = [string]$c.question
        Write-Host "[$counter/$totalRuns] $($c.id)  $question"

        try {
            $answer = Invoke-Chat -Url $BaseUrl -SessionId $sessionId -Question $question
            $test = Test-Keywords -Answer $answer -MustKeywords $c.must_keywords

            $rows += [pscustomobject]@{
                run = $r
                id = [string]$c.id
                category = [string]$c.category
                question = $question
                pass = [bool]$test.Pass
                must_total = [int]$test.MustTotal
                must_hit = [int]$test.MustHit
                missing = [string]$test.Missing
                answer_len = $answer.Length
                answer_preview = $(if ($null -eq $answer -or $answer.Length -eq 0) { "" } else { $answer.Substring(0, [Math]::Min(120, $answer.Length)).Replace("`r"," ").Replace("`n"," ") })
            }
        } catch {
            $rows += [pscustomobject]@{
                run = $r
                id = [string]$c.id
                category = [string]$c.category
                question = $question
                pass = $false
                must_total = if ($c.must_keywords) { $c.must_keywords.Count } else { 0 }
                must_hit = 0
                missing = "REQUEST_FAILED"
                answer_len = 0
                answer_preview = $_.Exception.Message
            }
        }
    }
}

try {
    $rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8 -Force
} catch {
    throw "Export-Csv failed for '$OutCsv': $($_.Exception.Message)"
}
if (-not (Test-Path -LiteralPath $OutCsv)) {
    throw "CSV was not created: $OutCsv"
}
Write-Host "CSV written : $OutCsv ($(Get-Item -LiteralPath $OutCsv).Length bytes)"
Write-Host ""

$all = @($rows).Count
$passCount = ($rows | Where-Object { $_.pass } | Measure-Object).Count
$passRate = if ($all -gt 0) { [Math]::Round(($passCount * 100.0 / $all), 2) } else { 0 }

Write-Host ""
Write-Host "================ EVAL SUMMARY ================"
Write-Host "BaseUrl    : $BaseUrl"
Write-Host "Dataset    : $DatasetPath"
Write-Host "Repeat     : $Repeat"
Write-Host "Total      : $all"
Write-Host "Pass       : $passCount"
Write-Host "Pass Rate  : $passRate %"
Write-Host "Result CSV : $OutCsv"
Write-Host "=============================================="

$byCategory = $rows | Group-Object category | Sort-Object Name
foreach ($g in $byCategory) {
    $n = $g.Count
    $p = ($g.Group | Where-Object { $_.pass } | Measure-Object).Count
    $rate = if ($n -gt 0) { [Math]::Round(($p * 100.0 / $n), 2) } else { 0 }
    Write-Host ("{0,-12} {1,3}/{2,-3}  {3,6}%" -f $g.Name, $p, $n, $rate)
}
