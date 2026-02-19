<#
.SYNOPSIS
  Stage 1: Capture baseline snapshot of BOTH projects before migration.
.DESCRIPTION
  Records file counts, sizes, auth users, collections, and app registrations.
  Saves baseline to a JSON file for post-migration comparison.
#>
param(
    [Parameter(Mandatory)][string]$SrcProject,
    [Parameter(Mandatory)][string]$DstProject,
    [string]$OutputDir = "./migration-audit"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STAGE 1: PRE-MIGRATION BASELINE AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$TS = Get-Date -Format "yyyyMMdd-HHmmss"

function Find-StorageBucket {
    param([string]$ProjectId)
    $bucketList = gcloud storage buckets list --project=$ProjectId --format="value(name)" 2>&1
    $found = $null
    foreach ($b in $bucketList) {
        if ($b -match "firebasestorage\.app$") { $found = $b; break }
    }
    if (-not $found) {
        foreach ($b in $bucketList) {
            if ($b -match "\.appspot\.com$") { $found = $b; break }
        }
    }
    return $found
}

function Get-BucketFileStats {
    param([string]$BucketName)
    $listing = gcloud storage ls -l --recursive "gs://$BucketName" 2>&1
    $fileCount = 0
    $totalBytes = 0
    foreach ($line in $listing) {
        if ($line -match "^\s+(\d+)\s+\d{4}-\d{2}-\d{2}") {
            $fileCount++
            $totalBytes += [long]$matches[1]
        }
    }
    return @{ Count = $fileCount; Bytes = $totalBytes }
}

function Get-AuthUserCount {
    param([string]$ProjectId, [string]$OutDir, [string]$Timestamp)
    $authFile = Join-Path $OutDir "auth-temp-$Timestamp.json"
    firebase auth:export $authFile --project $ProjectId --format=json 2>$null
    $userCount = 0
    if (Test-Path $authFile) {
        $data = Get-Content $authFile -Raw | ConvertFrom-Json
        if ($data.users) { $userCount = $data.users.Count }
        Remove-Item $authFile -ErrorAction SilentlyContinue
    }
    return $userCount
}

function Get-AppCount {
    param([string]$ProjectId)
    try {
        $apps = firebase apps:list --project $ProjectId 2>&1
    }
    catch {
        $apps = @()
    }
    $pipeChar = [char]0x2502
    $count = @($apps | Select-String -Pattern $pipeChar).Count
    return $count
}

# --- Audit SOURCE ---
Write-Host "--- Auditing SOURCE ($SrcProject) ---" -ForegroundColor Yellow

Write-Host "  Finding storage bucket..."
$srcBucket = Find-StorageBucket -ProjectId $SrcProject
Write-Host "  Bucket: $srcBucket"

Write-Host "  Counting storage files..."
$srcStorage = Get-BucketFileStats -BucketName $srcBucket
Write-Host "  Storage: $($srcStorage.Count) files, $([math]::Round($srcStorage.Bytes/1MB, 2)) MB"

Write-Host "  Counting auth users..."
$srcAuthCount = Get-AuthUserCount -ProjectId $SrcProject -OutDir $OutputDir -Timestamp $TS
Write-Host "  Auth: $srcAuthCount users"

Write-Host "  Listing app registrations..."
$srcAppCount = Get-AppCount -ProjectId $SrcProject
Write-Host "  Apps: $srcAppCount"

# --- Audit DESTINATION ---
Write-Host ""
Write-Host "--- Auditing DESTINATION ($DstProject) ---" -ForegroundColor Yellow

Write-Host "  Finding storage bucket..."
$dstBucket = Find-StorageBucket -ProjectId $DstProject
Write-Host "  Bucket: $dstBucket"

Write-Host "  Counting storage files..."
$dstStorage = Get-BucketFileStats -BucketName $dstBucket
Write-Host "  Storage: $($dstStorage.Count) files, $([math]::Round($dstStorage.Bytes/1MB, 2)) MB"

Write-Host "  Counting auth users..."
$dstAuthCount = Get-AuthUserCount -ProjectId $DstProject -OutDir $OutputDir -Timestamp $TS
Write-Host "  Auth: $dstAuthCount users"

Write-Host "  Listing app registrations..."
$dstAppCount = Get-AppCount -ProjectId $DstProject
Write-Host "  Apps: $dstAppCount"

# --- Save baseline ---
$baseline = @{
    CapturedAt  = (Get-Date).ToString("o")
    Source      = @{
        ProjectId     = $SrcProject
        StorageBucket = $srcBucket
        StorageCount  = $srcStorage.Count
        StorageBytes  = $srcStorage.Bytes
        AuthCount     = $srcAuthCount
        AppCount      = $srcAppCount
    }
    Destination = @{
        ProjectId     = $DstProject
        StorageBucket = $dstBucket
        StorageCount  = $dstStorage.Count
        StorageBytes  = $dstStorage.Bytes
        AuthCount     = $dstAuthCount
        AppCount      = $dstAppCount
    }
}
$baselinePath = Join-Path $OutputDir "baseline-$TS.json"
$baseline | ConvertTo-Json -Depth 5 | Out-File $baselinePath -Encoding utf8

# --- Summary ---
Write-Host ""
Write-Host "=== BASELINE SUMMARY ===" -ForegroundColor Cyan
Write-Host "Source:  $($srcStorage.Count) files, $([math]::Round($srcStorage.Bytes/1MB,2)) MB, $srcAuthCount users, $srcAppCount apps"
Write-Host "Dest:    $($dstStorage.Count) files, $([math]::Round($dstStorage.Bytes/1MB,2)) MB, $dstAuthCount users, $dstAppCount apps"
Write-Host "Saved:   $baselinePath"

Write-Host ""
Write-Host "[PIPELINE OUTPUT]"
Write-Host "SRC_BUCKET=$srcBucket"
Write-Host "DST_BUCKET=$dstBucket"
Write-Host "BASELINE_FILE=$baselinePath"

Write-Host ""
Write-Host "STAGE 1 COMPLETE" -ForegroundColor Green
exit 0
