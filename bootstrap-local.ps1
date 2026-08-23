param(
  [switch]$SkipTests,
  [switch]$SourceOnly,
  [string]$WorkDir = "$PSScriptRoot\.work\chat-on-steroids-plus"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-Command([string]$Name, [string]$Hint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name is required. $Hint"
  }
}

Require-Command git 'Install Git for Windows first.'
Require-Command node 'Install Node.js 22 LTS first.'
Require-Command npm 'Node.js must include npm.'

$nodeMajor = [int]((node -p "process.versions.node.split('.')[0]").Trim())
if ($nodeMajor -lt 22) { throw "Node.js 22+ is required; found $(node -v)." }

$upstream = 'https://github.com/totec448-spec/chat-on-steroids.git'
$patcher = Join-Path $PSScriptRoot 'scripts\plus-bootstrap.mjs'
$fixups = Join-Path $PSScriptRoot 'scripts\plus-fixups.mjs'
if (-not (Test-Path -LiteralPath $patcher)) { throw "Missing $patcher" }
if (-not (Test-Path -LiteralPath $fixups)) { throw "Missing $fixups" }

$parent = Split-Path -Parent $WorkDir
New-Item -ItemType Directory -Force -Path $parent | Out-Null
if (Test-Path -LiteralPath $WorkDir) {
  Write-Host "Removing previous worktree: $WorkDir"
  Remove-Item -LiteralPath $WorkDir -Recurse -Force
}

Write-Host 'Cloning Chat On Steroids 1.9.4 upstream...'
git clone --depth 1 $upstream $WorkDir
if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }

Push-Location $WorkDir
try {
  New-Item -ItemType Directory -Force -Path scripts | Out-Null
  Copy-Item -LiteralPath $patcher -Destination 'scripts\plus-bootstrap.mjs' -Force
  Copy-Item -LiteralPath $fixups -Destination 'scripts\plus-fixups.mjs' -Force

  Write-Host 'Applying Plus Bridge transport...'
  node scripts/plus-bootstrap.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Plus Bridge bootstrap patch failed' }
  node scripts/plus-fixups.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Plus Bridge fixups failed' }

  Write-Host 'Installing exact upstream dependencies...'
  npm ci
  if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }

  if (-not $SkipTests) {
    Write-Host 'Running TypeScript checks and tests...'
    npm run verify:ci
    if ($LASTEXITCODE -ne 0) { throw 'Verification failed; installer was not built.' }
  }

  if ($SourceOnly) {
    Write-Host "Patched source is ready at: $WorkDir"
    exit 0
  }

  Write-Host 'Building Windows x64 installer...'
  npm run dist:x64
  if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }

  $installer = Join-Path $WorkDir 'release\Chat-On-Steroids-Setup-x64.exe'
  if (-not (Test-Path -LiteralPath $installer)) { throw "Build completed without expected installer: $installer" }

  $outDir = Join-Path $PSScriptRoot 'dist'
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $dest = Join-Path $outDir 'Chat-On-Steroids-Plus-Setup-x64.exe'
  Copy-Item -LiteralPath $installer -Destination $dest -Force

  $extension = Join-Path $WorkDir 'extension'
  $extensionZip = Join-Path $outDir 'Chat-On-Steroids-Plus-Extension.zip'
  if (Test-Path -LiteralPath $extensionZip) { Remove-Item -LiteralPath $extensionZip -Force }
  Compress-Archive -Path "$extension\*" -DestinationPath $extensionZip -CompressionLevel Optimal

  $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Value "$hash  Chat-On-Steroids-Plus-Setup-x64.exe" -Encoding ascii

  Write-Host ''
  Write-Host 'DONE' -ForegroundColor Green
  Write-Host "Installer: $dest"
  Write-Host "Extension: $extensionZip"
  Write-Host "Patched source: $WorkDir"
} finally {
  Pop-Location
}
