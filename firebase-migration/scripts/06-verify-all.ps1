<#
.SYNOPSIS
  Stage 6: Final comprehensive parity check between two Firebase projects.
.DESCRIPTION
  Compares app registrations, storage (count + size), auth users,
  and functions. Produces PASS/FAIL verdict.
.PARAMETER SrcProject
  Source Firebase project ID
.PARAMETER DstProject
  Destination Firebase project ID
.PARAMETER SrcBucket
  Optional. Auto-discovers if not set.
.PARAMETER DstBucket
  Optional. Auto-discovers if not set.
#>
param(
    [Parameter(Mandatory)][string]$SrcProject,
    [Parameter(Mandatory)][string]$DstProject,
    [string]$SrcBucket,
    [string]$DstBucket
)

$ErrorActionPreference = "Continue"

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  STAGE 6: FINAL PARITY VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$allPassed = $true

# --- Helper: auto-discover bucket ---
function Find-FirebaseBucket {
    param([string]$ProjectId)
    $buckets = gcloud storage buckets list --project=$ProjectId --format="value(name)" 2>&1
    $bucket = ($buckets | Where-Object { $_ -match "firebasestorage\.app$" }) | Select-Object -First 1
    if (-not $bucket) { $bucket = ($buckets | Where-Object { $_ -match "\.appspot\.com$" }) | Select-Object -First 1 }
    return $bucket
}

if (-not $SrcBucket) { $SrcBucket = Find-FirebaseBucket -ProjectId $SrcProject }
if (-not $DstBucket) { $DstBucket = Find-FirebaseBucket -ProjectId $DstProject }

# --- CHECK 1: App Registrations ---
Write-Host "1. App Registrations" -ForegroundColor Yellow
$pipeChar = [char]0x2502
$srcApps = (firebase apps:list --project $SrcProject 2>&1 | Select-String -Pattern $pipeChar).Count
$dstApps = (firebase apps:list --project $DstProject 2>&1 | Select-String -Pattern $pipeChar).Count
if ($srcApps -eq $dstApps) {
    Write-Host "   PASS: $srcApps apps each" -ForegroundColor Green
}
else {
    Write-Host "   FAIL: Source=$srcApps, Dest=$dstApps" -ForegroundColor Red
    $allPassed = $false
}

# --- CHECK 2: Auth Users ---
Write-Host "2. Auth Users" -ForegroundColor Yellow
$TS = Get-Date -Format "yyyyMMdd-HHmmss"
firebase auth:export "./verify-src-$TS.json" --project $SrcProject --format=json 2>$null
firebase auth:export "./verify-dst-$TS.json" --project $DstProject --format=json 2>$null
$srcUsers = ((Get-Content "./verify-src-$TS.json" -Raw | ConvertFrom-Json).users).Count
$dstUsers = ((Get-Content "./verify-dst-$TS.json" -Raw | ConvertFrom-Json).users).Count
Remove-Item "./verify-src-$TS.json", "./verify-dst-$TS.json" -ErrorAction SilentlyContinue

if ($dstUsers -ge $srcUsers) {
    Write-Host "   PASS: Source=$srcUsers, Dest=$dstUsers" -ForegroundColor Green
}
else {
    Write-Host "   FAIL: Source=$srcUsers, Dest=$dstUsers (destination has fewer users)" -ForegroundColor Red
    $allPassed = $false
}

# --- CHECK 3: Storage File Count ---
Write-Host "3. Storage File Count" -ForegroundColor Yellow
function Get-BucketStats {
    param([string]$Bucket)
    $listing = gcloud storage ls -l --recursive "gs://$Bucket" 2>&1
    $count = 0; $size = 0
    foreach ($line in $listing) {
        if ($line -match '^\s+(\d+)\s+\d{4}-\d{2}-\d{2}') { $count++; $size += [long]$matches[1] }
    }
    return @{ Count = $count; Bytes = $size }
}
$srcStorage = Get-BucketStats -Bucket $SrcBucket
$dstStorage = Get-BucketStats -Bucket $DstBucket

if ($srcStorage.Count -eq $dstStorage.Count) {
    Write-Host "   PASS: $($srcStorage.Count) files each" -ForegroundColor Green
}
else {
    Write-Host "   FAIL: Source=$($srcStorage.Count), Dest=$($dstStorage.Count)" -ForegroundColor Red
    $allPassed = $false
}

# --- CHECK 4: Storage Total Size ---
Write-Host "4. Storage Total Size" -ForegroundColor Yellow
$srcMB = [math]::Round($srcStorage.Bytes / 1MB, 2)
$dstMB = [math]::Round($dstStorage.Bytes / 1MB, 2)
if ($srcStorage.Bytes -eq $dstStorage.Bytes) {
    Write-Host "   PASS: $srcMB MB each" -ForegroundColor Green
}
else {
    $diffMB = [math]::Round(($srcStorage.Bytes - $dstStorage.Bytes) / 1MB, 2)
    Write-Host "   FAIL: Source=$srcMB MB, Dest=$dstMB MB (diff=$diffMB MB)" -ForegroundColor Red
    $allPassed = $false
}

# --- CHECK 5: Cloud Functions ---
Write-Host "5. Cloud Functions" -ForegroundColor Yellow
$pipeChar2 = [char]0x2502
$srcFuncs = (firebase functions:list --project $SrcProject 2>&1 | Select-String -Pattern $pipeChar2).Count
$dstFuncs = (firebase functions:list --project $DstProject 2>&1 | Select-String -Pattern $pipeChar2).Count
if ($srcFuncs -eq $dstFuncs) {
    Write-Host "   PASS: $srcFuncs functions each" -ForegroundColor Green
}
else {
    Write-Host "   FAIL: Source=$srcFuncs, Dest=$dstFuncs" -ForegroundColor Red
    $allPassed = $false
}

# --- CHECK 6: Manual items ---
Write-Host "`n6. Manual Checks Required:" -ForegroundColor Yellow
Write-Host "   [ ] Firestore: Same collections and document counts"
Write-Host "   [ ] Firestore Rules: Identical between source and destination"
Write-Host "   [ ] Storage Rules: Identical between source and destination"
Write-Host "   [ ] Firestore Indexes: Same composite indexes"

# --- VERDICT ---
Write-Host "`n============================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "  [PASS] ALL AUTOMATED CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Complete manual checks above, then migration is done." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "  [FAIL] SOME CHECKS FAILED" -ForegroundColor Red
    Write-Host "  DO NOT proceed until all issues are resolved." -ForegroundColor Red
    exit 1
}
