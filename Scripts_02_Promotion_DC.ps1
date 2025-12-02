# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 02A : Promotion DC ROOT BRUXELLE (Crée la forêt)
# Fichier: 02-Promo-DC-Root-BRUXELLE.ps1
# Crée la forêt Belgique.lan avec site BRUXELLE
# ════════════════════════════════════════════════════════════════════════════


$DomainName = "Belgique.lan"
$SiteName = "BRUXELLE"
$DSRMPassword = ConvertTo-SecureString "P@ssword2025!DSRM" -AsPlainText -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PROMOTION DC ROOT - BRUXELLE" -ForegroundColor Cyan
Write-Host "Foret: $DomainName" -ForegroundColor Cyan
Write-Host "Site: $SiteName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n[VERIFICATION] Verification de l'IP..." -ForegroundColor Yellow

$IPCheck = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq "172.28.1.1" }

if ($IPCheck) {
    Write-Host "OK: IP 172.28.1.1 trouvee." -ForegroundColor Green
} else {
    Write-Host "ERREUR: L'IP 172.28.1.1 n'est pas configuree !" -ForegroundColor Red
    Break
}

Write-Host "`n[1/4] Installation des roles AD DS, DNS et DHCP..." -ForegroundColor Yellow

try {
    Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP -IncludeManagementTools
    Write-Host "OK: Roles installes" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n[2/4] Configuration DHCP pour VLANs..." -ForegroundColor Yellow

$DHCPScopes = @(
    @{ Name = "VLAN10-Admin";       Start = "172.28.10.50"; End = "172.28.10.150"; Subnet = "255.255.255.0" },
    @{ Name = "VLAN20-RD";          Start = "172.28.20.50"; End = "172.28.20.150"; Subnet = "255.255.255.0" },
    @{ Name = "VLAN30-IT";          Start = "172.28.30.50"; End = "172.28.30.150"; Subnet = "255.255.255.0" },
    @{ Name = "VLAN40-Commercial";  Start = "172.28.40.50"; End = "172.28.40.150"; Subnet = "255.255.255.0" },
    @{ Name = "VLAN50-Technique";   Start = "172.28.50.50"; End = "172.28.50.150"; Subnet = "255.255.255.0" },
    @{ Name = "VLAN99-VoIP";        Start = "172.28.99.50"; End = "172.28.99.150"; Subnet = "255.255.255.0" }
)

foreach ($Scope in $DHCPScopes) {
    try {
        Add-DhcpServerv4Scope -Name $Scope.Name -StartRange $Scope.Start -EndRange $Scope.End -SubnetMask $Scope.Subnet -State Active -ErrorAction SilentlyContinue
        Write-Host "OK: Scope cree: $($Scope.Name)" -ForegroundColor Green
    } catch {
        Write-Host "ATTENTION: Scope existant: $($Scope.Name)" -ForegroundColor Gray
    }
}

Write-Host "`n[3/4] Promotion en DC Root..." -ForegroundColor Yellow

try {
    Import-Module ADDSDeployment

    Install-ADDSForest -DomainName $DomainName -CreateDnsDelegation:$false -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -SafeModeAdministratorPassword $DSRMPassword -Force -Confirm:$false

    Write-Host "OK: Foret creee !" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "OK: PROMOTION REUSSIE" -ForegroundColor Green
Write-Host "Redemarrage automatique du serveur..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

## SCRIPT 02B : Promotion DC REPLICA NAMUR
# Fichier: 02-Promo-DC-Replica-NAMUR.ps1

$DomainName = "Belgique.lan"
$SourceDC = "172.28.1.1"
$SourceDCFQDN = "DC-BRUXELLE.Belgique.lan"
$SiteName = "NAMUR"
$DSRMPassword = ConvertTo-SecureString "P@ssword2025!DSRM" -AsPlainText -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PROMOTION DC REPLICA - NAMUR" -ForegroundColor Cyan
Write-Host "Domaine: $DomainName" -ForegroundColor Cyan
Write-Host "Source: $SourceDCFQDN ($SourceDC)" -ForegroundColor Cyan
Write-Host "Site: $SiteName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n[VERIFICATION] Avant de continuer..." -ForegroundColor Yellow

$IPCheck = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq "172.25.0.1" }

if ($IPCheck) {
    Write-Host "OK: IP 172.25.0.1 trouvee." -ForegroundColor Green
} else {
    Write-Host "ERREUR: L'IP 172.25.0.1 n'est pas configuree !" -ForegroundColor Red
    Break
}

Write-Host "`nIMPORTANT: Verifiez que..." -ForegroundColor Yellow
Write-Host "  1. BRUXELLE (172.28.1.1) est demarree" -ForegroundColor Gray
Write-Host "  2. Routage entre 172.28.x.x et 172.25.0.x fonctionne" -ForegroundColor Gray

Write-Host "`nTest: ping 172.28.1.1" -ForegroundColor Cyan
$TestPing = Test-Connection -ComputerName $SourceDC -Count 1 -Quiet -ErrorAction SilentlyContinue

if ($TestPing) {
    Write-Host "OK: Ping reussi vers BRUXELLE" -ForegroundColor Green
} else {
    Write-Host "ERREUR: Impossible de ping BRUXELLE !" -ForegroundColor Red
    Write-Host "Verifiez le firewall et le routage" -ForegroundColor Red
    Break
}

Write-Host "`n[1/2] Installation des roles AD DS et DNS..." -ForegroundColor Yellow

try {
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools
    Write-Host "OK: Roles installes" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n[CREDENTIALS] Entrez les identifiants Belgique\Administrateur" -ForegroundColor Yellow
$Credential = Get-Credential -Message "Belgique\Administrateur"

if (-not $Credential) {
    Write-Host "ERREUR: Credentials annulees" -ForegroundColor Red
    Break
}

Write-Host "`n[2/2] Promotion en DC Replica..." -ForegroundColor Yellow

try {
    Import-Module ADDSDeployment

    New-ADReplicationSite -Name $SiteName -Confirm:$false -ErrorAction SilentlyContinue

    Install-ADDSDomainController -DomainName $DomainName -Credential $Credential -SiteName $SiteName -ReplicaOrNewDomain Replica -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -SafeModeAdministratorPassword $DSRMPassword -Force -Confirm:$false

    Write-Host "OK: Replica creee !" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "OK: PROMOTION REPLICA REUSSIE" -ForegroundColor Green
Write-Host "Redemarrage automatique du serveur..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nApres redemarrage sur NAMUR (DC Replica):" -ForegroundColor Cyan
Write-Host "  Connexion: BELGIQUE\Administrateur" -ForegroundColor Gray
Write-Host "  Lecture/Ecriture - Replica complet de Bruxelle" -ForegroundColor Gray

# SCRIPT 02C : Promotion DC READ-ONLY (RODC) MONS
# Fichier: 02-Promo-DC-RODC-MONS.ps1

$DomainName = "Belgique.lan"
$SourceDC = "172.25.0.1"
$SourceDCFQDN = "DC-NAMUR.Belgique.lan"
$SiteName = "MONS"
$DSRMPassword = ConvertTo-SecureString "P@ssword2025!DSRM" -AsPlainText -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PROMOTION DC READ-ONLY (RODC) - MONS" -ForegroundColor Cyan
Write-Host "Domaine: $DomainName" -ForegroundColor Cyan
Write-Host "Source: $SourceDCFQDN ($SourceDC)" -ForegroundColor Cyan
Write-Host "Site: $SiteName (Lecture seule)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n[VERIFICATION] Avant de continuer..." -ForegroundColor Yellow

$IPCheck = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq "172.27.0.1" }

if ($IPCheck) {
    Write-Host "OK: IP 172.27.0.1 trouvee." -ForegroundColor Green
} else {
    Write-Host "ERREUR: L'IP 172.27.0.1 n'est pas configuree !" -ForegroundColor Red
    Break
}

Write-Host "`nIMPORTANT: Verifiez que..." -ForegroundColor Yellow
Write-Host "  1. NAMUR (172.25.0.1) est demarree" -ForegroundColor Gray
Write-Host "  2. Routage fonctionne: 172.27.x.x <-> 172.25.x.x" -ForegroundColor Gray

Write-Host "`nTest: ping 172.25.0.1" -ForegroundColor Cyan
$TestPing = Test-Connection -ComputerName $SourceDC -Count 1 -Quiet -ErrorAction SilentlyContinue

if ($TestPing) {
    Write-Host "OK: Ping reussi vers NAMUR" -ForegroundColor Green
} else {
    Write-Host "ERREUR: Impossible de ping NAMUR !" -ForegroundColor Red
    Break
}

Write-Host "`n[1/2] Installation des roles AD DS et DNS..." -ForegroundColor Yellow

try {
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools
    Write-Host "OK: Roles installes" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n[CREDENTIALS] Entrez les identifiants Belgique\Administrateur" -ForegroundColor Yellow
$Credential = Get-Credential -Message "Belgique\Administrateur"

if (-not $Credential) {
    Write-Host "ERREUR: Credentials annulees" -ForegroundColor Red
    Break
}

Write-Host "`n[2/2] Promotion en DC Read-Only (RODC)..." -ForegroundColor Yellow

try {
    Import-Module ADDSDeployment

    New-ADReplicationSite -Name $SiteName -Confirm:$false -ErrorAction SilentlyContinue

    Install-ADDSDomainController -DomainName $DomainName -Credential $Credential -SiteName $SiteName -ReplicaOrNewDomain Replica -ReadOnlyReplica:$true -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -SafeModeAdministratorPassword $DSRMPassword -Force -Confirm:$false

    Write-Host "OK: RODC creee !" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: $_" -ForegroundColor Red
    Break
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "OK: PROMOTION RODC REUSSIE" -ForegroundColor Green
Write-Host "Redemarrage automatique du serveur..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nApres redemarrage sur MONS (RODC):" -ForegroundColor Cyan
Write-Host "  Lecture seule - Pas de modifications AD" -ForegroundColor Gray
Write-Host "  Auth locale si Bruxelle/Namur inaccessibles" -ForegroundColor Gray
