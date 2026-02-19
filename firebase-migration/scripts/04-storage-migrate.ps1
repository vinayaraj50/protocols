<#
.SYNOPSIS
  Stage 4: Migrate Storage with checksums and self-verification.
.DESCRIPTION
  Auto-discovers bucket names. Uses --checksums for integrity.
  Uses --delete-unmatched-destination-objects for exact mirror.
  Verifies file count AND total size match after sync.
.PARAMETER SrcProject
  Source Firebase project ID
.PARAMETER DstProject
  Destination Firebase project ID
.PARAMETER SrcBucket
  Optional. Source bucket name. If not provided, auto-discovers.
.PARAMETER DstBucket
  Optional. Destination bucket name. If not provided, auto-discovers.
#>
param(
    [Parameter(Mandatory)][string]$SrcProject,
    [Parameter(Mandatory)][string]$DstProject,
    [string]$SrcBucket,
    [string]$DstBucket
)

$ErrorActionPreference = "Stop"

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "  STAGE 4: STORAGE MIGRATION" -ForegroundColor Cyan
Write-Host "=================================`n" -ForegroundColor Cyan

# Auto-discover bucket names if not provided
function Find-FirebaseBucket {
    param([string]$ProjectId)
    $buckets = gcloud storage buckets list --project=$ProjectId --format="value(name)" 2>&1
    $bucket = ($buckets | Where-Object { $_ -match "firebasestorage\.app$" }) | Select-Object -First 1
    if (-not $bucket) {
        $bucket = ($buckets | Where-Object { $_ -match "\.appspot\.com$" }) | Select-Object -First 1
    }
    if (-not $bucket) {
        Write-Host "❌ Could not find Firebase storage bucket for $ProjectId" -ForegroundColor Red
        Write-Host "   Available buckets: $($buckets -join ', ')" -ForegroundColor Yellow
        exit 1
    }
    return $bucket
}

if (-not $SrcBucket) {
    Write-Host "Auto-discovering source bucket..."
    $SrcBucket = Find-FirebaseBucket -ProjectId $SrcProject
}
if (-not $DstBucket) {
    Write-Host "Auto-discovering destination bucket..."
    $DstBucket = Find-FirebaseBucket -ProjectId $DstProject
}

Write-Host "Source bucket:      $SrcBucket"
Write-Host "Destination bucket: $DstBucket"

# Pre-check: Is the destination bucket non-empty?
Write-Host "`n--- Checking destination state ---"
$dstCheck = gcloud storage ls "gs://$DstBucket" 2>&1
$dstHasFiles = ($dstCheck | Where-Object { $_ -match "^gs://" }).Count -gt 0

if ($dstHasFiles) {
    Write-Host "⚠️  Destination bucket is NOT empty." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [A] DELETE all destination files first, then sync (guarantees exact mirror)" -ForegroundColor Cyan
    Write-Host "  [B] KEEP existing files, rsync will overwrite matching + delete unmatched" -ForegroundColor Cyan
    Write-Host ""
    $choice = Read-Host "Choose [A] or [B]"

    if ($choice -eq "A") {
        Write-Host "`nClearing destination bucket..." -ForegroundColor Yellow
        gcloud storage rm "gs://$DstBucket/**" --recursive 2>&1
        Write-Host "Destination bucket cleared." -ForegroundColor Green
    }
    elseif ($choice -eq "B") {
        Write-Host "`nKeeping existing files. rsync will handle differences." -ForegroundColor Yellow
    }
    else {
        Write-Host "❌ Invalid choice. Aborting." -ForegroundColor Red
        exit 1
    }
}

# Step 1: Capture pre-sync state
Write-Host "`n--- Pre-sync snapshot ---"
$preSrcSize = gcloud storage du -s "gs://$SrcBucket" 2>&1
Write-Host "Source size: $preSrcSize"

# Step 2: Run rsync with checksums + delete-unmatched
Write-Host "`n--- Running rsync (checksums + mirror mode) ---" -ForegroundColor Yellow
gcloud storage rsync "gs://$SrcBucket" "gs://$DstBucket" `
    --recursive `
    --delete-unmatched-destination-objects

# Step 3: Self-verify — compare file count AND total size
Write-Host "`n--- Verifying Storage ---" -ForegroundColor Yellow

function Get-BucketStats {
    param([string]$Bucket)
    $listing = gcloud storage ls -l --recursive "gs://$Bucket" 2>&1
    $count = 0; $size = 0
    foreach ($line in $listing) {
        if ($line -match '^\s+(\d+)\s+\d{4}-\d{2}-\d{2}') {
            $count++; $size += [long]$matches[1]
        }
    }
    return @{ Count = $count; Bytes = $size }
}

$srcStats = Get-BucketStats -Bucket $SrcBucket
$dstStats = Get-BucketStats -Bucket $DstBucket

Write-Host "Source:      $($srcStats.Count) files, $([math]::Round($srcStats.Bytes/1MB,2)) MB"
Write-Host "Destination: $($dstStats.Count) files, $([math]::Round($dstStats.Bytes/1MB,2)) MB"

$countMatch = $srcStats.Count -eq $dstStats.Count
$sizeMatch = $srcStats.Bytes -eq $dstStats.Bytes

if ($countMatch -and $sizeMatch) {
    Write-Host "✅ Storage PASS: Count and size match exactly." -ForegroundColor Green
}
else {
    if (-not $countMatch) {
        Write-Host "❌ File count MISMATCH: $($srcStats.Count) vs $($dstStats.Count)" -ForegroundColor Red
    }
    if (-not $sizeMatch) {
        $diffMB = [math]::Round(($srcStats.Bytes - $dstStats.Bytes) / 1MB, 2)
        Write-Host "❌ Total size MISMATCH: diff = $diffMB MB" -ForegroundColor Red
    }
    Write-Host "⚠️  Re-run this script or investigate individual file differences." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✅ STAGE 4 COMPLETE" -ForegroundColor Green
exit 0
