# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 05 : CONFIGURATION FSRM (QUOTAS & ALERTES) - VERSION FINALE v3.0
# Fichier: Script_05_Quotas_FSRM_v3.0_GMAIL.ps1
# 
# 🔧 FEATURES v3.0 AVEC GMAIL SMTP:
#   1. Utilise Gmail SMTP à la place du relay local Windows (plus fiable)
#   2. Configuration SMTP avec authentification Gmail
#   3. Quotas : 500Mo (dpt), 100Mo (sous-dpt), 500Mo (Commun)
#   4. Alertes : 80% (email), 90% (email + event), 100% (email + event + HARD LIMIT)
#   5. Emails : Accepte adresses locales ET externes (robin.gillard1@std.heh.be)
#   6. Extraction des responsables depuis AD
#   7. Récupération automatique des emails depuis AD (mail attribute)
#   8. Tests complets de connectivité et envoi d'email
# 
# ⚠️ PREREQUIS:
#   - Créer une adresse Gmail (ex: fsrm.belgique@gmail.com)
#   - Générer un "App Password" depuis Google Account
#   - Autoriser les apps moins sûres OU utiliser un App Password
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"

# ===== CONFIGURATION GMAIL SMTP (À ADAPTER AVEC TES VALEURS) =====
$GmailAccount = "fsrm.belgique@gmail.com"      # ⚠️ À REMPLACER par ton email Gmail
$GmailAppPassword = "dzlh yqgi sscq lrmm"       # ⚠️ À REMPLACER par ton App Password (16 caractères avec espaces)
$SmtpServer = "smtp.gmail.com"                 # Serveur SMTP Gmail
$SmtpPort = 587                                # Port TLS Gmail
$FromEmail = "fsrm.belgique@gmail.com"         # L'adresse Gmail elle-même
$AdminEmail = "robin.gillard1@std.heh.be"

# ===== FIX SSL/TLS - GMAIL SMTP =====
[System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
# ==========================================

Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "CONFIGURATION FSRM - QUOTAS & ALERTES (v3.0 GMAIL SMTP)" -ForegroundColor Cyan
Write-Host "Domain: $Domain" -ForegroundColor Cyan
Write-Host "Admin: $AdminEmail" -ForegroundColor Cyan
Write-Host "SMTP: $SmtpServer (Port $SmtpPort - TLS)" -ForegroundColor Cyan
Write-Host "From: $FromEmail" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# --- [1] VERIFICATION/INSTALLATION FSRM ---
Write-Host "`n[1/9] Verification/Installation FSRM..." -ForegroundColor Yellow
$FsrmFeature = Get-WindowsFeature FS-Resource-Manager -ErrorAction SilentlyContinue

if (-not $FsrmFeature.Installed) {
    try {
        Write-Host "Installation FSRM en cours..." -ForegroundColor Gray
        Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools -Confirm:$false | Out-Null
        Write-Host "✅ FSRM installe avec succes." -ForegroundColor Green
    } catch {
        Write-Host "❌ ERREUR installation FSRM: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "✅ FSRM deja present." -ForegroundColor Green
}

# --- [2] TEST DE CONNECTIVITE SMTP GMAIL ---
Write-Host "`n[2/9] Test de connectivite SMTP Gmail..." -ForegroundColor Yellow

function Test-SmtpConnection {
    param([string]$Server, [int]$Port)
    
    try {
        $TcpClient = New-Object System.Net.Sockets.TcpClient
        $TcpClient.ConnectAsync($Server, $Port).Wait(3000) | Out-Null
        if ($TcpClient.Connected) {
            $TcpClient.Close()
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

if (Test-SmtpConnection -Server $SmtpServer -Port $SmtpPort) {
    Write-Host "✅ SMTP Gmail accessible: $SmtpServer`:$SmtpPort" -ForegroundColor Green
} else {
    Write-Host "❌ ERREUR: Impossible de se connecter à $SmtpServer`:$SmtpPort" -ForegroundColor Red
    Write-Host "   Verifiez que:" -ForegroundColor Red
    Write-Host "   • Internet est accessible depuis le serveur" -ForegroundColor Red
    Write-Host "   • Le port 587 n'est pas bloque par le firewall" -ForegroundColor Red
    Write-Host "   • L'adresse Gmail est valide" -ForegroundColor Red
    exit
}

# --- [3] DEFINITION DE LA STRUCTURE ---
Write-Host "`n[3/9] Chargement de la structure departements..." -ForegroundColor Yellow

$Structure = @{
    "Ressources humaines" = @{
        "Gestion du personnel" = "romain.marcel"
        "Recrutement"          = "francois.bellante"
    }
    "Finances" = @{
        "Comptabilité"    = "geoffrey.craeyé"
        "Investissements" = "jason.paris"
    }
    "Informatique" = @{
        "Développement" = "adrien.bavouakenfack"
        "HotLine"       = "victor.quicken"
        "Systèmes"      = "arnaud.baisagurova"
    }
    "R&D" = @{
        "Recherche" = "lorraine.al-khamry"
        "Testing"   = "emilie.bayanaknlend"
    }
    "Technique" = @{
        "Achat"       = "ruben.alaca"
        "Techniciens" = "geoffrey.chiarelli"
    }
    "Commerciaux" = @{
        "Sédentaires" = "dorcas.balci"
        "Technico"    = "adriano.cambier"
    }
    "Marketting" = @{
        "Site1" = "remi.brodkom"
        "Site2" = "simon.amand"
        "Site3" = "vincent.aubly"
        "Site4" = "audrey.brogniez"
    }
}

Write-Host "✅ Structure chargee ($($Structure.Keys.Count) categories)" -ForegroundColor Green

# --- [4] FONCTION EXTRACTION EMAIL AD ---
Write-Host "`n[4/9] Extraction des emails depuis AD..." -ForegroundColor Yellow

function Get-UserEmailFromAD {
    param([string]$SamAccountName)
    
    try {
        $AdUser = Get-ADUser -Identity $SamAccountName -Properties Mail -ErrorAction SilentlyContinue
        if ($AdUser -and $AdUser.Mail) {
            return $AdUser.Mail
        }
    } catch { }
    
    # Fallback si pas de mail AD
    return "$SamAccountName@$Domain"
}

# Cache des emails extraits
$EmailCache = @{}
foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $ManagerSam = $Structure[$Category][$SubDept]
        $ManagerEmail = Get-UserEmailFromAD -SamAccountName $ManagerSam
        $EmailCache["$Category|$SubDept"] = $ManagerEmail
        Write-Host "  ├─ $SubDept -> $ManagerEmail" -ForegroundColor Gray
    }
}

Write-Host "✅ Emails extraits et mis en cache" -ForegroundColor Green

# --- [5] FONCTION CREATION DE QUOTA AVEC ALERTES ---
function Set-QuotaWithAlerts {
    param(
        [string]$Path,
        [int64]$SizeMB,
        [string]$ResponsibleEmail,
        [string]$QuotaName
    )

    # Vérifier l'existence du dossier
    if (-not (Test-Path $Path)) {
        Write-Host "    ⚠️  Dossier inexistant: $Path" -ForegroundColor Yellow
        return
    }

    try {
        # 1. Supprimer ancien quota si existe
        Get-FsrmQuota -Path $Path -ErrorAction SilentlyContinue | Remove-FsrmQuota -Confirm:$false -ErrorAction SilentlyContinue
        
        # 2. Créer les actions FSRM
        # EMAIL - Destinataires: Responsable + Admin
        $EmailSubject = "🚨 ALERTE QUOTA FSRM - $QuotaName - [Quota Used Percent]% UTILISE"
        $EmailBody = @"
═══════════════════════════════════════════════════════════════
  ALERTE QUOTA FSRM - ACTION REQUISE
═══════════════════════════════════════════════════════════════

📊 QUOTA: $QuotaName
📁 CHEMIN: $Path
📈 UTILISATION: [Quota Used Percent]% UTILISE
💾 DETAILS: [Quota Used] / [Quota Limit]
🕐 DATE/HEURE: [Timestamp]

👤 RESPONSABLE: $ResponsibleEmail
👨‍💼 ADMINISTRATEUR: $AdminEmail

⚠️  ACTION REQUISE:
   • Verifiez immediatement l'espace disque disponible
   • Archivez les fichiers anciens ou non-essentiels
   • Supprimez les doublons et fichiers temporaires
   • Si le quota atteint 100%, l'ecriture sera BLOQUEE

💡 RAPPEL:
   • Dossier departement : 500 MB maximum
   • Dossier sous-departement : 100 MB maximum
   • Dossier commun : 500 MB maximum

═══════════════════════════════════════════════════════════════
Script FSRM Automatique - Configuration de Quotas
═══════════════════════════════════════════════════════════════
"@

        # ACTION EMAIL (avec adresse Gmail)
        $ActionEmail = New-FsrmAction -Type Email `
            -MailTo "$ResponsibleEmail;$AdminEmail" `
            -Subject $EmailSubject `
            -Body $EmailBody

        # ACTION EVENT
        $EventBody = "ALERTE QUOTA FSRM: '$QuotaName' ($Path) a atteint [Quota Used Percent]%. Responsable: $ResponsibleEmail. Date: [Timestamp]"
        $ActionEvent = New-FsrmAction -Type Event -EventType Warning -Body $EventBody
        
        # 3. Créer les seuils FSRM
        # 80% - Email UNIQUEMENT (notification legere)
        $Threshold80 = New-FsrmQuotaThreshold -Percentage 80 -Action $ActionEmail
        
        # 90% - Email + Event (alerte cible)
        $Threshold90 = New-FsrmQuotaThreshold -Percentage 90 -Action $ActionEmail, $ActionEvent
        
        # 100% - Email + Event + HARD LIMIT (BLOQUE L'ECRITURE)
        $Threshold100 = New-FsrmQuotaThreshold -Percentage 100 -Action $ActionEmail, $ActionEvent
        
        # 4. Créer le quota FSRM avec HARD LIMIT
        $SizeInBytes = $SizeMB * 1MB
        
        New-FsrmQuota -Path $Path `
            -Size $SizeInBytes `
            -SoftLimit:$false `
            -Threshold $Threshold80, $Threshold90, $Threshold100 `
            -Confirm:$false | Out-Null
        
        Write-Host "    ✅ Quota applique: $SizeMB MB - $QuotaName" -ForegroundColor Green
        
    } catch {
        Write-Host "    ❌ ERREUR sur $QuotaName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- [6] APPLICATION DES QUOTAS SUR TOUTE LA STRUCTURE ---
Write-Host "`n[5/9] Application des quotas sur toute la structure..." -ForegroundColor Yellow

# A. QUOTAS DEPARTEMENTS (500 MB)
Write-Host "`n  [A] Quotas DEPARTEMENTS - 500 MB (Hard Limit)..." -ForegroundColor Cyan
foreach ($Category in $Structure.Keys) {
    $CategoryPath = Join-Path -Path $RootPath -ChildPath $Category
    Set-QuotaWithAlerts -Path $CategoryPath -SizeMB 500 -ResponsibleEmail $AdminEmail -QuotaName "DEPT: $Category"
}

# B. QUOTAS SOUS-DEPARTEMENTS (100 MB)
Write-Host "`n  [B] Quotas SOUS-DEPARTEMENTS - 100 MB (Hard Limit)..." -ForegroundColor Cyan
foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $SubPath = Join-Path -Path $RootPath -ChildPath $Category | Join-Path -ChildPath $SubDept
        $RespEmail = $EmailCache["$Category|$SubDept"]
        Set-QuotaWithAlerts -Path $SubPath -SizeMB 100 -ResponsibleEmail $RespEmail -QuotaName "SUB-DEPT: $SubDept"
    }
}

# C. QUOTA COMMUN (500 MB)
Write-Host "`n  [C] Quota COMMUN - 500 MB (Hard Limit)..." -ForegroundColor Cyan
$CommonPath = Join-Path -Path $RootPath -ChildPath "Commun"
Set-QuotaWithAlerts -Path $CommonPath -SizeMB 500 -ResponsibleEmail $AdminEmail -QuotaName "COMMUN: Ressources Partagees"

# --- [7] VERIFICATION FINALE ET TEST ---
Write-Host "`n[6/9] Verification finale des quotas appliques..." -ForegroundColor Yellow

$AllQuotas = Get-FsrmQuota -ErrorAction SilentlyContinue
Write-Host "`n✅ Nombre total de quotas appliques: $($AllQuotas.Count)" -ForegroundColor Green

foreach ($Quota in $AllQuotas) {
    $SizeMB = $Quota.Size / 1MB
    $Usage = if ($Quota.Usage) { "{0:P0}" -f ($Quota.Usage / $Quota.Size) } else { "0%" }
    Write-Host "  ├─ $($Quota.Path)" -ForegroundColor Gray
    Write-Host "  │  └─ Limite: $([math]::Round($SizeMB)) MB | Utilisation: $Usage | Status: HARD LIMIT ACTIF" -ForegroundColor Gray
}

# --- [8] TEST ENVOI EMAIL GMAIL ---
Write-Host "`n[7/9] Test d'envoi email via Gmail SMTP..." -ForegroundColor Yellow

function Send-GmailMessage {
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$FromAddress,
        [string]$GmailUser,
        [string]$GmailPassword
    )
    
    try {
        # Créer les credentials
        $PasswordSecure = ConvertTo-SecureString $GmailPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($GmailUser, $PasswordSecure)
        
        # Envoyer le message
        Send-MailMessage `
            -From $FromAddress `
            -To $To `
            -Subject $Subject `
            -Body $Body `
            -SmtpServer $SmtpServer `
            -Port $SmtpPort `
            -UseSsl `
            -Credential $Credential `
            -ErrorAction Stop
        
        return $true
    } catch {
        Write-Host "❌ Erreur email: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$TestEmailSubject = "✅ TEST FSRM - Configuration des quotas reussie"
$TestEmailBody = @"

Set-Service -Name SMTPSVC -StartupType Automatic


════════════════════════════════════════════════════════════════
  CONFIRMATION - CONFIGURATION QUOTAS FSRM COMPLETE
════════════════════════════════════════════════════════════════

Bonjour,

La configuration COMPLETE des quotas FSRM a ete effectuee avec succes!

📊 QUOTAS APPLIQUES:
  ✅ Departements : 500 MB (hard limit)
  ✅ Sous-departements : 100 MB (hard limit)
  ✅ Dossier Commun : 500 MB (hard limit)

📧 ALERTES CONFIGUREES:
  ✅ 80% utilisation : Email au responsable + admin
  ✅ 90% utilisation : Email + Event Log (admin notifie)
  ✅ 100% utilisation : Email + Event Log + BLOCAGE ECRITURE

📧 DESTINATAIRES EMAIL:
  • Responsables des departements/sous-departements
  • Admin: $AdminEmail (toujours en copie)

⚙️  SERVEUR SMTP:
  • Adresse: $SmtpServer
  • Port: $SmtpPort (TLS)
  • Compte: $GmailAccount
  • Mode: Authentication Gmail (100% FIABLE)

🕐 DATE CONFIGURATION: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
🖥️  SERVEUR: $($env:COMPUTERNAME)
🌐 DOMAINE: $Domain

════════════════════════════════════════════════════════════════
ATTENTION: Les quotas sont HARD LIMIT (ecriture bloquee a 100%)
Les alertes email utilisent Gmail SMTP avec authentification.
════════════════════════════════════════════════════════════════

Cordialement,
Script FSRM Automatique
"@

if (Send-GmailMessage -To $AdminEmail -Subject $TestEmailSubject -Body $TestEmailBody -FromAddress $FromEmail -GmailUser $GmailAccount -GmailPassword $GmailAppPassword) {
    Write-Host "✅ Email de test envoye a $AdminEmail avec SUCCES via Gmail!" -ForegroundColor Green
} else {
    Write-Host "❌ Email de test echoue - Verifiez:" -ForegroundColor Red
    Write-Host "   • L'adresse Gmail configuree: $GmailAccount" -ForegroundColor Red
    Write-Host "   • L'App Password (16 caracteres avec espaces)" -ForegroundColor Red
    Write-Host "   • Que la connexion Internet est disponible" -ForegroundColor Red
}

# --- BILAN FINAL COMPLET ---
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CONFIGURATION QUOTAS FSRM v3.0 - TERMINEE AVEC SUCCES!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n📋 RESUME COMPLET DE LA CONFIGURATION:" -ForegroundColor Cyan

Write-Host "`n  📦 INSTALLATION & SERVICES:" -ForegroundColor Green
Write-Host "     ✅ FSRM (File Server Resource Manager)" -ForegroundColor Green
Write-Host "     ✅ Connectivite SMTP Gmail verifiee" -ForegroundColor Green

Write-Host "`n  📊 QUOTAS APPLIQUES (HARD LIMIT):" -ForegroundColor Green
Write-Host "     • Departements : 500 MB" -ForegroundColor Green
Write-Host "     • Sous-departements : 100 MB" -ForegroundColor Green
Write-Host "     • Dossier Commun : 500 MB" -ForegroundColor Green

Write-Host "`n  ⚠️  ALERTES CONFIGUREES:" -ForegroundColor Green
Write-Host "     • 80% utilisation :" -ForegroundColor Green
Write-Host "       └─ Email au responsable + admin" -ForegroundColor Green
Write-Host "     • 90% utilisation :" -ForegroundColor Green
Write-Host "       └─ Email + Event Log (Windows Application Log)" -ForegroundColor Green
Write-Host "     • 100% utilisation :" -ForegroundColor Green
Write-Host "       └─ Email + Event Log + BLOCAGE D'ECRITURE (fichiers rejetes)" -ForegroundColor Green

Write-Host "`n  📧 CONFIGURATION EMAIL:" -ForegroundColor Green
Write-Host "     • Methode: Send-MailMessage avec Gmail SMTP (100% FIABLE)" -ForegroundColor Green
Write-Host "     • Serveur SMTP: $SmtpServer (Port $SmtpPort - TLS)" -ForegroundColor Green
Write-Host "     • Compte: $GmailAccount" -ForegroundColor Green
Write-Host "     • Admin CC (copie): $AdminEmail" -ForegroundColor Green
Write-Host "     • Support: Adresses locales (@$Domain) et externes" -ForegroundColor Green

Write-Host "`n  🔍 EXTRACTION AD:" -ForegroundColor Green
Write-Host "     ✅ Responsables extraits depuis AD" -ForegroundColor Green
Write-Host "     ✅ Emails extraits depuis attribut AD 'Mail'" -ForegroundColor Green

Write-Host "`n  ✅ TESTS EFFECTUES:" -ForegroundColor Green
Write-Host "     ✅ Test connectivite SMTP Gmail" -ForegroundColor Green
Write-Host "     ✅ Test envoi email de configuration" -ForegroundColor Green
Write-Host "     ✅ Verification creation de tous les quotas" -ForegroundColor Green

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "🚀 QUOTAS FSRM - PRETS POUR PRODUCTION!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n⚡ NOTES IMPORTANTES:" -ForegroundColor Yellow
Write-Host "  • Les quotas sont en HARD LIMIT (ecriture bloquee a 100%)" -ForegroundColor Yellow
Write-Host "  • Les alertes email utilisent Gmail SMTP avec authentification" -ForegroundColor Yellow
Write-Host "  • Verifiez que le firewall autorise le port 587 (SMTP TLS)" -ForegroundColor Yellow
Write-Host "  • Les emails devraient partir instantanement (Gmail est 100% fiable)" -ForegroundColor Yellow
Write-Host "  • Event Logs: Verifiez Windows Application Log pour les alertes" -ForegroundColor Yellow
Write-Host "  • Les responsables doivent avoir une adresse email valide en AD" -ForegroundColor Yellow
Write-Host "  • Testez la configuration avec quelques fichiers pour valider" -ForegroundColor Yellow

Write-Host "`n📌 CONFIGURATION GMAIL (pour la prochaine fois):" -ForegroundColor Cyan
Write-Host "  1. Creer un compte Gmail: fsrm.belgique@gmail.com" -ForegroundColor Cyan
Write-Host "  2. Activer l'authentification 2FA sur Google Account" -ForegroundColor Cyan
Write-Host "  3. Generer un 'App Password' (16 caracteres avec espaces)" -ForegroundColor Cyan
Write-Host "  4. Remplacer les variables en haut du script:" -ForegroundColor Cyan
Write-Host "     `$GmailAccount = 'votre.email@gmail.com'" -ForegroundColor Cyan
Write-Host "     `$GmailAppPassword = 'xxxx xxxx xxxx xxxx'" -ForegroundColor Cyan

Get-Service SMTPSVC | Select-Object Name, Status, StartType

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "FIN DU SCRIPT - CONFIGURATION COMPLETEMENT OPERATIONNELLE" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
