# One-time setup: creates the self-signed Nyxplorer code-signing certificate and stores it as GitHub Actions secrets
# (NYXPLORER_CERT_PFX, NYXPLORER_CERT_PASSWORD). Every release must be signed with the same certificate, otherwise
# installed copies cannot update in place. Keep the backup .pfx this script writes somewhere safe and private.
#
# Requires: GitHub CLI logged in (gh auth login).

param(
    [string]$Repository = "Shaiyon69/Nyxplorer",
    [string]$Subject = "CN=Shaiyon69",
    [string]$BackupDir = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Nyxplorer-signing"),
    [int]$Years = 10
)

$ErrorActionPreference = "Stop"

$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Subject `
    -FriendlyName "Nyxplorer code signing" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA -KeyLength 3072 `
    -NotAfter (Get-Date).AddYears($Years) `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

$passwordText = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
$password = ConvertTo-SecureString $passwordText -AsPlainText -Force

New-Item -ItemType Directory -Force $BackupDir | Out-Null
$pfxPath = Join-Path $BackupDir "Nyxplorer-signing.pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null
Set-Content (Join-Path $BackupDir "Nyxplorer-signing.password.txt") $passwordText -NoNewline
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"

[Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath)) | gh secret set NYXPLORER_CERT_PFX --repo $Repository
$passwordText | gh secret set NYXPLORER_CERT_PASSWORD --repo $Repository

Write-Host "Certificate $Subject ($($cert.Thumbprint)) valid until $($cert.NotAfter.ToString('yyyy-MM-dd'))"
Write-Host "Secrets NYXPLORER_CERT_PFX and NYXPLORER_CERT_PASSWORD set on $Repository"
Write-Host "Backup saved to $BackupDir - keep it private; you need it if you ever rebuild the secrets."
