# Windows release build for tbgui. Run from the repo root in PowerShell:
#   .\scripts\build-windows.ps1 -Version v1.0.0
# (in a monorepo checkout: .\gui\scripts\build-windows.ps1 -Version v1.0.0)
#
# Needs Flutter with Windows desktop support. Produces:
#   dist\tbgui-<ver>-windows-x86_64.zip   (tbgui.exe + tbproxy.exe + openvpn.exe)
param([string]$Version = "v1.0.0")

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if ((Split-Path $ScriptDir -Leaf) -eq "gui") { $RepoRoot = (Resolve-Path "$ScriptDir\..\..").Path }  # monorepo
else { $RepoRoot = (Resolve-Path "$ScriptDir\..").Path }                                             # standalone repo
if (Test-Path "$RepoRoot\gui") { $GuiSrc = "$RepoRoot\gui" } else { $GuiSrc = $RepoRoot }

$CliRepo = if ($env:CLI_REPO) { $env:CLI_REPO } else { "https://github.com/FossilizedProgrammer/tbproxy-cli" }

function Log($msg) { Write-Host "[build-windows] $msg" }

# 1) tbproxy.exe + openvpn.exe: sibling checkout or matching CLI release.
$TbProxyExe = ""
if (Test-Path "$RepoRoot\cli\tbproxy.exe") {
  $TbProxyExe = "$RepoRoot\cli\tbproxy.exe"
} else {
  New-Item -ItemType Directory -Force -Path "$RepoRoot\.vendor" | Out-Null
  $Zip = "$RepoRoot\.vendor\tbproxy-$Version-windows-amd64.zip"
  if (!(Test-Path $Zip)) {
    Log "Downloading tbproxy $Version ..."
    Invoke-WebRequest -Uri "$CliRepo/releases/download/$Version/tbproxy-$Version-windows-amd64.zip" -OutFile $Zip
  }
  Expand-Archive -Path $Zip -DestinationPath "$RepoRoot\.vendor" -Force
  $TbProxyExe = "$RepoRoot\.vendor\tbproxy-windows-amd64.exe"
  if ((Test-Path "$RepoRoot\.vendor\openvpn.exe") -and !(Test-Path "$RepoRoot\openvpn.exe")) {
    Copy-Item "$RepoRoot\.vendor\openvpn.exe" "$RepoRoot\openvpn.exe"
  }
}
if (!(Test-Path $TbProxyExe)) { throw "tbproxy.exe missing: $TbProxyExe" }

# 2) Flutter Windows build.
if (!(Test-Path "$GuiSrc\windows")) { throw "windows/ scaffold missing in $GuiSrc" }
Log "Building GUI ..."
Push-Location $GuiSrc
try {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally { Pop-Location }
$Rel = "$GuiSrc\build\windows\x64\runner\Release"
if (!(Test-Path "$Rel\tbgui.exe")) { throw "no binary produced in $Rel" }

# 3) Bundle + zip.
Copy-Item $TbProxyExe "$Rel\tbproxy.exe" -Force
$OpenVpn = "$RepoRoot\openvpn.exe"
if (Test-Path $OpenVpn) {
  Copy-Item $OpenVpn "$Rel\openvpn.exe" -Force
  Log "Bundled openvpn.exe"
} else {
  Log "WARNING: $OpenVpn not found — zip will use system openvpn"
}
New-Item -ItemType Directory -Force -Path "$RepoRoot\dist" | Out-Null
$OutZip = "$RepoRoot\dist\tbgui-$Version-windows-x86_64.zip"
if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
Compress-Archive -Path "$Rel\*" -DestinationPath $OutZip
Log "Done: $OutZip"
Log "Run tbgui.exe as administrator (right-click -> Run as administrator)."
