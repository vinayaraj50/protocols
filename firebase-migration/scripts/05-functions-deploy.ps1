<#
.SYNOPSIS
  Stage 5: Deploy Cloud Functions, Firestore Rules, Indexes, and Storage Rules.
.PARAMETER DstProject
  Destination Firebase project ID
.PARAMETER ProjectDir
  Path to the Firebase project directory (where firebase.json lives)
#>
param(
  [Parameter(Mandatory)][string]$DstProject,
  [string]$ProjectDir = "."
)

$ErrorActionPreference = "Stop"

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "  STAGE 5: FUNCTIONS & RULES DEPLOY" -ForegroundColor Cyan
Write-Host "=====================================`n" -ForegroundColor Cyan

# Step 1: Deploy Functions
Write-Host "Deploying Cloud Functions to $DstProject..."
firebase deploy --only functions --project $DstProject --cwd $ProjectDir

# Step 2: Deploy Rules & Indexes
Write-Host "`nDeploying Firestore Rules, Indexes, and Storage Rules..."
firebase deploy --only firestore:rules, firestore:indexes, storage --project $DstProject --cwd $ProjectDir

# Step 3: Self-verify
Write-Host "`n--- Verifying Functions ---" -ForegroundColor Yellow
$funcs = firebase functions:list --project $DstProject 2>&1
$pipeChar = [char]0x2502
$funcCount = ($funcs | Select-String -Pattern $pipeChar).Count
Write-Host "Deployed functions: $funcCount"
Write-Host $funcs

if ($funcCount -gt 0) {
  Write-Host "✅ Functions deployed successfully." -ForegroundColor Green
}
else {
  Write-Host "⚠️  No functions found. Verify if source project had functions." -ForegroundColor Yellow
}

Write-Host "`n✅ STAGE 5 COMPLETE" -ForegroundColor Green
exit 0
