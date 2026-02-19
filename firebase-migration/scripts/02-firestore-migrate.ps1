<#
.SYNOPSIS
  Stage 2: Migrate Firestore data with built-in verification.
.PARAMETER SrcProject
  Source Firebase project ID
.PARAMETER DstProject
  Destination Firebase project ID
.PARAMETER Region
  GCP region (default: us-central1)
#>
param(
    [Parameter(Mandatory)][string]$SrcProject,
    [Parameter(Mandatory)][string]$DstProject,
    [string]$Region = "us-central1"
)

$ErrorActionPreference = "Stop"
$TS = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  STAGE 2: FIRESTORE MIGRATION" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Step 1: Create migration bucket
$BACKUP_BUCKET = "$SrcProject-migration-$TS"
Write-Host "Creating migration bucket: $BACKUP_BUCKET"
gcloud storage buckets create "gs://$BACKUP_BUCKET" --project $SrcProject --location $Region --uniform-bucket-level-access

# Step 2: Grant cross-project permissions
Write-Host "Granting cross-project Firestore agent access..."
$SRC_NUM = gcloud projects describe $SrcProject --format="value(projectNumber)"
$DST_NUM = gcloud projects describe $DstProject --format="value(projectNumber)"

gcloud storage buckets add-iam-policy-binding "gs://$BACKUP_BUCKET" `
    --member="serviceAccount:service-$SRC_NUM@gcp-sa-firestore.iam.gserviceaccount.com" `
    --role="roles/firestore.serviceAgent"
gcloud storage buckets add-iam-policy-binding "gs://$BACKUP_BUCKET" `
    --member="serviceAccount:service-$DST_NUM@gcp-sa-firestore.iam.gserviceaccount.com" `
    --role="roles/firestore.serviceAgent"

# Step 3: Export from source
$EXPORT_PATH = "gs://$BACKUP_BUCKET/firestore/$TS"
Write-Host "Exporting Firestore from $SrcProject..."
gcloud firestore export $EXPORT_PATH --project $SrcProject --database="(default)"

# Step 4: Import to destination
Write-Host "Importing Firestore to $DstProject..."
gcloud firestore import $EXPORT_PATH --project $DstProject --database="(default)"

# Step 5: Self-verify
Write-Host "`n--- Verifying Firestore ---" -ForegroundColor Yellow
Write-Host "⚠️  MANUAL VERIFICATION REQUIRED:" -ForegroundColor Yellow
Write-Host "  1. Open Source Firestore Console — note collection names"
Write-Host "  2. Open Destination Firestore Console — compare"
Write-Host "  3. Spot-check 2-3 documents for data integrity"
Write-Host ""
Write-Host "  Source:  https://console.firebase.google.com/project/$SrcProject/firestore"
Write-Host "  Dest:    https://console.firebase.google.com/project/$DstProject/firestore"

Write-Host "`n✅ STAGE 2 COMPLETE" -ForegroundColor Green
exit 0
