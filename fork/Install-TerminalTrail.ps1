#Requires -RunAsAdministrator
# Installs the Terminal Trail MSIX from this folder.
# The package is signed with a self-signed certificate, so Windows has to trust
# TerminalTrail.cer first. It goes into Local Machine > Trusted People, which only
# lets it vouch for packages, not for websites or drivers.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# certutil instead of Import-Certificate: Windows PowerShell launched from PowerShell 7 inherits
# its PSModulePath, picks up the wrong security module and has no Cert: drive.
certutil -addstore TrustedPeople .\TerminalTrail.cer | Out-Null
if ($LASTEXITCODE) { throw "certutil failed with $LASTEXITCODE" }

$package = Get-ChildItem -Filter 'CascadiaPackage*.msix' | Select-Object -First 1
$dependencies = Get-ChildItem .\Dependencies -Filter *.appx | Select-Object -ExpandProperty FullName
Add-AppxPackage -Path $package.FullName -DependencyPath $dependencies -ForceUpdateFromAnyVersion

Write-Host 'Installed. To make it the default terminal: Settings > System > For developers > Terminal > Terminal Trail.'
