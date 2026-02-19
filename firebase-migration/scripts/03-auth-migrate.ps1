<#
.SYNOPSIS
  Stage 3: Migrate Auth users with built-in verification.
.PARAMETER SrcProject
  Source Firebase project ID
.PARAMETER DstProject
  Destination Firebase project ID
.PARAMETER HashAlgo
  Hash algorithm (default: SCRYPT)
.PARAMETER HashRounds
  Hash rounds from source console
.PARAMETER HashMemCost
  Memory cost from source console
.PARAMETER HashSaltSeparator
  Base64 salt separator from source console
.PARAMETER HashSignerKey
  Base64 signer key from source console
#>
param(
    [Parameter(Mandatory)][string]$SrcProject,
    [Parameter(Mandatory)][string]$DstProject,
    [string]$HashAlgo = "SCRYPT",
    [Parameter(Mandatory)][string]$HashRounds,
    [Parameter(Mandatory)][string]$HashMemCost,
    [Parameter(Mandatory)][string]$HashSaltSeparator,
    [Parameter(Mandatory)][string]$HashSignerKey
)

$ErrorActionPreference = "Stop"
$TS = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "  STAGE 3: AUTH MIGRATION" -ForegroundColor Cyan
Write-Host "==============================`n" -ForegroundColor Cyan

# Validate hash params are not placeholders
if ($HashRounds -match '^<.*>$' -or $HashMemCost -match '^<.*>$') {
    Write-Host "❌ FATAL: Hash parameters still contain placeholder values." -ForegroundColor Red
    exit 1
}

# Step 1: Export users
$authFile = "./auth-export-$TS.json"
Write-Host "Exporting users from $SrcProject..."
firebase auth:export $authFile --project $SrcProject --format=json

$srcCount = ((Get-Content $authFile -Raw | ConvertFrom-Json).users).Count
Write-Host "  Exported: $srcCount users"

# Step 2: Import users
Write-Host "Importing users to $DstProject..."
firebase auth:import $authFile --project $DstProject `
    --hash-algo=$HashAlgo `
    --rounds=$HashRounds `
    --mem-cost=$HashMemCost `
    --salt-separator=$HashSaltSeparator `
    --signer-key=$HashSignerKey

# Step 3: Self-verify
Write-Host "`n--- Verifying Auth ---" -ForegroundColor Yellow
$verifyFile = "./auth-verify-dst-$TS.json"
firebase auth:export $verifyFile --project $DstProject --format=json 2>$null
$dstCount = ((Get-Content $verifyFile -Raw | ConvertFrom-Json).users).Count

if ($dstCount -ge $srcCount) {
    Write-Host "✅ Auth PASS: Source=$srcCount, Destination=$dstCount" -ForegroundColor Green
}
else {
    Write-Host "❌ Auth FAIL: Source=$srcCount, Destination=$dstCount" -ForegroundColor Red
    exit 1
}

# Cleanup
Remove-Item $authFile, $verifyFile -ErrorAction SilentlyContinue

Write-Host "`n✅ STAGE 3 COMPLETE" -ForegroundColor Green
exit 0
