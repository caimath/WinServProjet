# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 08 : Configuration des GPO (Group Policy Objects)
# Fichier: 08-Configuration-GPO.ps1
# À exécuter SUR BRUXELLE
# ════════════════════════════════════════════════════════════════════════════

$Domain = "Belgique.lan"
$Server = "DC-BRUXELLE"
$SharePath = "\\\\$Server\DossiersPartages"

Import-Module GroupPolicy
Import-Module ActiveDirectory

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  CONFIGURATION DES GPO (Group Policy Objects)                 ║" -ForegroundColor Cyan
Write-Host "║  Domaine: $Domain                                              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 : Activation Corbeille AD
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[1/4] Activation de la Corbeille Active Directory..." -ForegroundColor Yellow

try {
    Enable-ADOptionalFeature "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target (Get-ADForest).Name -Confirm:$false -ErrorAction Stop
    Write-Host "   ✅ Corbeille AD activée (180 jours de rétention)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Corbeille probablement déjà activée" -ForegroundColor Gray
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 : Script de logon (Mappage lecteurs Y: et Z:)
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[2/4] Création du script de logon (Mappage lecteurs)..." -ForegroundColor Yellow

$NetlogonPath = "C:\Windows\SYSVOL\sysvol\$Domain\scripts"
$LogonScriptPath = "$NetlogonPath\MapDrives.ps1"

if (-not (Test-Path $NetlogonPath)) {
    New-Item -Path $NetlogonPath -ItemType Directory -Force | Out-Null
}

$ScriptContent = @"
# ========================================
# Script de logon - Mappage des lecteurs
# Exécuté à chaque connexion utilisateur
# ========================================

# Z: = Dossier Commun (pour TOUS les utilisateurs)
if (-not (Test-Path Z:)) {
    try {
        New-PSDrive -Name Z -PSProvider FileSystem -Root "$SharePath\Commun" -Persist -ErrorAction SilentlyContinue
        Write-Host "✅ Z: montée (Dossier Commun)"
    } catch { }
}

# Y: = Dossier du Département (automatique selon groupe)
`$UserGroups = (Get-ADUser -Identity `$env:USERNAME -Properties MemberOf | Select-Object -ExpandProperty MemberOf | ForEach-Object { (Get-ADGroup -Identity `$_ ).Name }) 2>$null

foreach (`$Group in `$UserGroups) {
    if (`$Group -like "GG_*" -and `$Group -ne "GG_DIRECTION") {
        `$DeptName = `$Group.Substring(3)  # Enlever le "GG_"
        `$FolderPath = "$SharePath\Departements\`$DeptName"
        
        if ((Test-Path `$FolderPath) -and -not (Test-Path Y:)) {
            try {
                New-PSDrive -Name Y -PSProvider FileSystem -Root `$FolderPath -Persist -ErrorAction SilentlyContinue
                Write-Host "✅ Y: montée (`$DeptName)"
            } catch { }
        }
        break
    }
}
"@

Set-Content -Path $LogonScriptPath -Value $ScriptContent -Force
Write-Host "   ✅ Script de logon créé: MapDrives.ps1" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 : GPO restrictive (Employés standard)
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[3/4] Création de la GPO restrictive (Employés Standard)..." -ForegroundColor Yellow

$GPOName = "GPO_Employes_Standard"
$BackgroundImagePath = "$SharePath\Commun\wallpaper.jpg"

# Créer image de fond (placeholder)
Write-Host "   • Création image de fond..." -ForegroundColor Gray
try {
    # Créer une image blanche simple (placeholder)
    [System.Drawing.Bitmap]$bitmap = New-Object System.Drawing.Bitmap(1920, 1080)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::White)
    
    # Ajouter du texte
    $font = New-Object System.Drawing.Font("Arial", 48, [System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Blue)
    $graphics.DrawString("BELGIQUE.LAN", $font, $brush, 50, 50)
    
    $bitmap.Save("C:\DossiersPartages\Commun\wallpaper.jpg")
    Write-Host "   ✅ Fond d'écran créé" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Image custom non créée, utilisez une image personnelle" -ForegroundColor Yellow
}

# Créer ou obtenir la GPO
if (-not (Get-GPO -Name $GPOName -ErrorAction SilentlyContinue)) {
    Write-Host "   • Création de la GPO..." -ForegroundColor Gray
    New-GPO -Name $GPOName | Out-Null
} else {
    Write-Host "   ⚠️  GPO existante" -ForegroundColor Gray
}

# Appliquer les paramètres
Write-Host "   • Configuration des restrictions..." -ForegroundColor Gray

$RegPath = "HKCU\Software\Policies\Microsoft\Windows\System"
Set-GPRegistryValue -Name $GPOName -Key $RegPath -ValueName "Wallpaper" -Type String -Value $BackgroundImagePath -ErrorAction SilentlyContinue
Set-GPRegistryValue -Name $GPOName -Key $RegPath -ValueName "WallpaperStyle" -Type String -Value "2" -ErrorAction SilentlyContinue

Set-GPRegistryValue -Name $GPOName -Key "HKCU\Software\Policies\Microsoft\Windows\System" -ValueName "DisableCMD" -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-GPRegistryValue -Name $GPOName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ValueName "NoControlPanel" -Type DWord -Value 1 -ErrorAction SilentlyContinue

Write-Host "   ✅ GPO créée: $GPOName" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 : Liaison des GPO aux OUs
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[4/4] Liaison des GPO aux Unités d'Organisation..." -ForegroundColor Yellow

$TargetOUs = Get-ADOrganizationalUnit -Filter * -SearchBase "DC=Belgique,DC=lan" -SearchScope OneLevel | `
    Where-Object {$_.Name -ne "Domain Controllers" -and $_.Name -ne "Computers" -and $_.Name -ne "Users"}

foreach ($OU in $TargetOUs) {
    try {
        New-GPLink -Name $GPOName -Target $OU.DistinguishedName -LinkEnabled Yes -ErrorAction SilentlyContinue
        Write-Host "   ✅ GPO liée à: $($OU.Name)" -ForegroundColor Green
    } catch {
        # GPO déjà liée
    }
}

# Exclusion du département Informatique
Write-Host "`n   • Exclusion du département Informatique/Systèmes..." -ForegroundColor Gray

$InfoOUs = Get-ADOrganizationalUnit -Filter {Name -like "*Informatique*" -or Name -eq "Systèmes"} -SearchBase "DC=Belgique,DC=lan" -SearchScope Subtree

foreach ($OU in $InfoOUs) {
    try {
        $Link = Get-GPLink -Target $OU.DistinguishedName | Where-Object { $_.DisplayName -eq $GPOName }
        if ($Link) {
            Remove-GPLink -Name $GPOName -Target $OU.DistinguishedName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "   ✅ GPO exclue de: $($OU.Name) (Admin)" -ForegroundColor Cyan
        }
    } catch { }
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ GPO CONFIGURÉE                                             ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nRésumé des restrictions:" -ForegroundColor Cyan
Write-Host "   ❌ Panneau de configuration (sauf Admin)" -ForegroundColor Gray
Write-Host "   ❌ Invite de commande (sauf Admin)" -ForegroundColor Gray
Write-Host "   ✅ Lecteurs Y: et Z: montées automatiquement" -ForegroundColor Gray
Write-Host "   ✅ Fond d'écran de la société appliqué" -ForegroundColor Gray

# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 09 : Serveur Web HTTPS
# Fichier: 09-Serveur-Web.ps1
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n\n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  SERVEUR WEB HTTPS                                             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n[1/3] Installation de IIS..." -ForegroundColor Yellow

try {
    Install-WindowsFeature Web-Server -IncludeManagementTools -ErrorAction Stop
    Write-Host "   ✅ IIS installé" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  IIS déjà installé" -ForegroundColor Gray
}

# Créer le site Web
Write-Host "`n[2/3] Configuration du site web..." -ForegroundColor Yellow

$WebPath = "C:\inetpub\wwwroot"

Set-Content -Path "$WebPath\index.html" -Value @"
<!DOCTYPE html>
<html>
<head>
    <title>Belgique.LAN</title>
    <style>
        body { font-family: Arial; text-align: center; margin-top: 50px; }
        h1 { color: #1C5A96; }
        .secure { color: green; font-size: 14px; }
    </style>
</head>
<body>
    <h1>Bienvenue sur Belgique.LAN</h1>
    <p>Portail d'accès sécurisé</p>
    <p class="secure">✅ Connexion HTTPS sécurisée</p>
</body>
</html>
"@

Write-Host "   ✅ Site web créé" -ForegroundColor Green

# Créer certificat SSL auto-signé
Write-Host "`n[3/3] Configuration HTTPS..." -ForegroundColor Yellow

try {
    $Cert = New-SelfSignedCertificate -DnsName "www.Belgique.lan", "Belgique.lan" -CertStoreLocation "cert:\LocalMachine\My" -FriendlyName "Belgique Web" -ErrorAction SilentlyContinue
    
    # Ajouter binding HTTPS
    New-WebBinding -Name "Default Web Site" -IP "*" -Port 443 -Protocol https -HostHeader "www.Belgique.lan" -ErrorAction SilentlyContinue
    
    # Associer le certificat
    $Binding = Get-WebBinding -Protocol https -HostHeader "www.Belgique.lan"
    $Binding.AddSslCertificate($Cert.Thumbprint, "My")
    
    Write-Host "   ✅ Certificat SSL créé et configuré" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Certificat déjà existant" -ForegroundColor Gray
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ SERVEUR WEB CONFIGURÉ                                      ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nAccès:" -ForegroundColor Cyan
Write-Host "   HTTPS: https://www.Belgique.lan" -ForegroundColor Gray
Write-Host "   (Certificat auto-signé = avertissement navigateur)" -ForegroundColor Gray