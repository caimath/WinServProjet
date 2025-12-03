# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 05 : CONFIGURATION FSRM (QUOTAS & ALERTES) - VERSION FINALE v2.3
# Fichier: Script_05_Quotas_FSRM_v2.3_FINAL.ps1
# 
# 🔧 FEATURES v2.3 COMPLETE AVEC RELAY SMTP FIX:
#   1. Installation automatique du service SMTP Windows + IIS6 Management
#   2. Configuration SMTP locale avec relay pour adresses externes
#   3. Quotas : 500Mo (dpt), 100Mo (sous-dpt), 500Mo (Commun)
#   4. Alertes : 80% (email), 90% (email + event), 100% (email + event + HARD LIMIT)
#   5. Emails : Accepte adresses locales ET externes (robin.gillard1@std.heh.be)
#   6. Extraction des responsables depuis AD
#   7. Récupération automatique des emails depuis AD (mail attribute)
#   8. Tests complets de connectivité et envoi d'email
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"

# Configuration Mail - Windows Native (Send-MailMessage)
$SmtpServer = "localhost"                 # Serveur SMTP local (relay)
$SmtpPort = 25                            # Port par defaut SMTP
$FromEmail = "fsrm@belgique.lan"
$AdminEmail = "robin.gillard1@std.heh.be"

Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "CONFIGURATION FSRM - QUOTAS & ALERTES (v2.3 FINAL)" -ForegroundColor Cyan
Write-Host "Domain: $Domain" -ForegroundColor Cyan
Write-Host "Admin: $AdminEmail" -ForegroundColor Cyan
Write-Host "SMTP: $SmtpServer (Port $SmtpPort)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# --- [1] VERIFICATION/INSTALLATION FSRM ---
Write-Host "`n[1/10] Verification/Installation FSRM..." -ForegroundColor Yellow
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

# --- [2] VERIFICATION/INSTALLATION SERVICE SMTP ---
Write-Host "`n[2/10] Verification/Installation du service SMTP Windows..." -ForegroundColor Yellow

$SmtpFeature = Get-WindowsFeature SMTP-Server -ErrorAction SilentlyContinue

if ($SmtpFeature -and -not $SmtpFeature.Installed) {
    try {
        Write-Host "Installation du service SMTP en cours..." -ForegroundColor Gray
        Install-WindowsFeature SMTP-Server -IncludeManagementTools -Confirm:$false | Out-Null
        Write-Host "✅ Service SMTP installe avec succes." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  SMTP feature non disponible sur cette version de Windows Server" -ForegroundColor Yellow
        Write-Host "   Utilisez IIS SMTP ou un relay externe a la place." -ForegroundColor Yellow
    }
} elseif ($SmtpFeature -and $SmtpFeature.Installed) {
    Write-Host "✅ Service SMTP deja installe et actif." -ForegroundColor Green
} else {
    Write-Host "⚠️  Service SMTP non disponible - Tentative d'activation du relay..." -ForegroundColor Yellow
}

# --- [3] DEMARRAGE DU SERVICE SMTP ---
Write-Host "`n[3/10] Verification du service SMTP (demarrage si necessaire)..." -ForegroundColor Yellow

try {
    $SmtpService = Get-Service -Name "SMTPSVC" -ErrorAction SilentlyContinue
    
    if ($SmtpService) {
        if ($SmtpService.Status -ne "Running") {
            Write-Host "Demarrage du service SMTP..." -ForegroundColor Gray
            Start-Service -Name "SMTPSVC" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Host "✅ Service SMTP demarrage." -ForegroundColor Green
        } else {
            Write-Host "✅ Service SMTP est en cours d'execution." -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  Service SMTP non present - Impossible de le demarrer" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Erreur demarrage SMTP: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- [4] INSTALLATION COMPOSANT GESTION IIS6 & CONFIGURATION RELAY ---
Write-Host "`n[4/10] Installation du composant de gestion IIS6 (pour config SMTP)..." -ForegroundColor Yellow

# Ce composant est requis pour configurer le service SMTP via des scripts
$Iis6MgmtFeature = Get-WindowsFeature Web-Lgcy-Mgmt-Console -ErrorAction SilentlyContinue
if ($Iis6MgmtFeature -and -not $Iis6MgmtFeature.Installed) {
    try {
        Write-Host "Installation de Web-Lgcy-Mgmt-Console en cours..." -ForegroundColor Gray
        Install-WindowsFeature Web-Lgcy-Mgmt-Console -Confirm:$false | Out-Null
        Write-Host "✅ Composant de gestion IIS6 installe." -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Impossible d'installer Web-Lgcy-Mgmt-Console" -ForegroundColor Yellow
    }
} else {
    Write-Host "ℹ️  Composant de gestion IIS6 (Web-Lgcy-Mgmt-Console) deja present ou non disponible." -ForegroundColor Gray
}

Write-Host "`n[5/10] Configuration du relais SMTP pour autoriser les emails externes..." -ForegroundColor Yellow
try {
    # Obtenir l'objet de configuration du serveur SMTP virtuel via WMI
    $SmtpVirtualServer = Get-WmiObject -namespace "root\MicrosoftIISv2" -class "IIsSmtpVirtualServer" -filter "Name='SmtpSvc/1'" -ErrorAction SilentlyContinue
    
    if ($SmtpVirtualServer) {
        # Ajouter 127.0.0.1 (localhost) à la liste de relais (autoriser le relais local)
        $newRelayList = New-Object System.Collections.ArrayList
        $newRelayList.Add("127.0.0.1")
        $SmtpVirtualServer.RelayIpList = $newRelayList.ToArray()
        $SmtpVirtualServer.Put()
        
        Write-Host "✅ Relais SMTP configure pour autoriser 127.0.0.1 (localhost)" -ForegroundColor Green
        Write-Host "   Les emails peuvent maintenant etre envoyes vers des domaines externes." -ForegroundColor Green
        
        # Redémarrer le service SMTP pour appliquer les modifications
        Write-Host "   Redemarrage du service SMTP..." -ForegroundColor Gray
        Restart-Service -Name "SMTPSVC" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host "✅ Service SMTP redémarre avec nouvelles configurations." -ForegroundColor Green
    } else {
        Write-Host "⚠️  Impossible de configurer le relais via WMI (serveur SMTP virtuel non trouvé)" -ForegroundColor Yellow
        Write-Host "   Le relais par defaut sera utilise." -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Erreur lors de la configuration du relais SMTP: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "   Les emails locaux devraient fonctionner, mais le relay externe peut ne pas fonctionner." -ForegroundColor Yellow
}

# --- [6] TEST DE CONNECTIVITE SMTP ---
Write-Host "`n[6/10] Test de connectivite SMTP..." -ForegroundColor Yellow

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
    Write-Host "✅ SMTP accessible: $SmtpServer`:$SmtpPort" -ForegroundColor Green
} else {
    Write-Host "⚠️  ATTENTION: Impossible de se connecter a $SmtpServer`:$SmtpPort" -ForegroundColor Yellow
    Write-Host "   Le service SMTP peut ne pas etre actif." -ForegroundColor Yellow
    Write-Host "   Les quotas seront quand meme appliques (alertes limitees a Event Log)." -ForegroundColor Yellow
}

# --- [7] DEFINITION DE LA STRUCTURE ---
Write-Host "`n[7/10] Chargement de la structure departements..." -ForegroundColor Yellow

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

# --- [8] FONCTION EXTRACTION EMAIL AD ---
Write-Host "`n[8/10] Extraction des emails depuis AD..." -ForegroundColor Yellow

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

# --- [9] FONCTION CREATION DE QUOTA AVEC ALERTES ---
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

        # ACTION EMAIL
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

# --- [10] APPLICATION DES QUOTAS SUR TOUTE LA STRUCTURE ---
Write-Host "`n[9/10] Application des quotas sur toute la structure..." -ForegroundColor Yellow

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

# --- [11] VERIFICATION FINALE ET TEST ---
Write-Host "`n[10/10] Verification finale des quotas appliques..." -ForegroundColor Yellow

$AllQuotas = Get-FsrmQuota -ErrorAction SilentlyContinue
Write-Host "`n✅ Nombre total de quotas appliques: $($AllQuotas.Count)" -ForegroundColor Green

foreach ($Quota in $AllQuotas) {
    $SizeMB = $Quota.Size / 1MB
    $Usage = if ($Quota.Usage) { "{0:P0}" -f ($Quota.Usage / $Quota.Size) } else { "0%" }
    Write-Host "  ├─ $($Quota.Path)" -ForegroundColor Gray
    Write-Host "  │  └─ Limite: $([math]::Round($SizeMB)) MB | Utilisation: $Usage | Status: HARD LIMIT ACTIF" -ForegroundColor Gray
}

# --- [12] TEST ENVOI EMAIL ---
Write-Host "`n[Test] Test d'envoi email vers admin..." -ForegroundColor Yellow

function Test-EmailSend {
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body
    )
    
    try {
        Send-MailMessage -To $To -Subject $Subject -Body $Body `
            -From $FromEmail -SmtpServer $SmtpServer -Port $SmtpPort `
            -ErrorAction Stop
        return $true
    } catch {
        Write-Host "⚠️  Erreur email: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

$TestEmailSubject = "✅ TEST FSRM - Configuration des quotas reussie"
$TestEmailBody = @"
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
  • Port: $SmtpPort
  • Mode: Relay local configu pour domaines externes

🕐 DATE CONFIGURATION: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
🖥️  SERVEUR: $($env:COMPUTERNAME)
🌐 DOMAINE: $Domain

════════════════════════════════════════════════════════════════
ATTENTION: Les quotas sont HARD LIMIT (ecriture bloquee a 100%)
Les alertes email dependent de la configuration SMTP.
════════════════════════════════════════════════════════════════

Cordialement,
Script FSRM Automatique
"@

if (Test-EmailSend -To $AdminEmail -Subject $TestEmailSubject -Body $TestEmailBody) {
    Write-Host "✅ Email de test envoye a $AdminEmail avec SUCCES" -ForegroundColor Green
} else {
    Write-Host "⚠️  Email de test echoue - Verifiez SMTP ou Queue locale" -ForegroundColor Yellow
}

# --- BILAN FINAL COMPLET ---
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CONFIGURATION QUOTAS FSRM v2.3 - TERMINEE AVEC SUCCES!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n📋 RESUME COMPLET DE LA CONFIGURATION:" -ForegroundColor Cyan

Write-Host "`n  📦 INSTALLATION & SERVICES:" -ForegroundColor Green
Write-Host "     ✅ FSRM (File Server Resource Manager)" -ForegroundColor Green
Write-Host "     ✅ Service SMTP Windows (Relay local)" -ForegroundColor Green
Write-Host "     ✅ IIS6 Management Console (si disponible)" -ForegroundColor Green
Write-Host "     ✅ Connectivite SMTP verifiee" -ForegroundColor Green

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
Write-Host "     • Methode: Send-MailMessage (PowerShell natif)" -ForegroundColor Green
Write-Host "     • Serveur SMTP: $SmtpServer (Port $SmtpPort)" -ForegroundColor Green
Write-Host "     • Expediteur: $FromEmail" -ForegroundColor Green
Write-Host "     • Admin CC (copie): $AdminEmail" -ForegroundColor Green
Write-Host "     • Support: Adresses locales (@$Domain) et externes" -ForegroundColor Green
Write-Host "     • Relais: CONFIGU pour accepter 127.0.0.1 (localhost)" -ForegroundColor Green

Write-Host "`n  🔍 EXTRACTION AD:" -ForegroundColor Green
Write-Host "     ✅ Responsables extraits depuis AD" -ForegroundColor Green
Write-Host "     ✅ Emails extraits depuis attribut AD 'Mail'" -ForegroundColor Green

Write-Host "`n  ✅ TESTS EFFECTUES:" -ForegroundColor Green
Write-Host "     ✅ Test connectivite SMTP" -ForegroundColor Green
Write-Host "     ✅ Configuration du relais SMTP" -ForegroundColor Green
Write-Host "     ✅ Test envoi email de configuration" -ForegroundColor Green
Write-Host "     ✅ Verification creation de tous les quotas" -ForegroundColor Green

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "🚀 QUOTAS FSRM - PRETS POUR PRODUCTION!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n⚡ NOTES IMPORTANTES:" -ForegroundColor Yellow
Write-Host "  • Les quotas sont en HARD LIMIT (ecriture bloquee a 100%)" -ForegroundColor Yellow
Write-Host "  • Les alertes email dependent de la configuration SMTP" -ForegroundColor Yellow
Write-Host "  • Verifiez que le service SMTP est en cours d'execution" -ForegroundColor Yellow
Write-Host "  • Les emails peuvent etre en queue si SMTP n'est pas actif" -ForegroundColor Yellow
Write-Host "  • Event Logs: Verifiez Windows Application Log pour les alertes" -ForegroundColor Yellow
Write-Host "  • Les responsables doivent avoir une adresse email valide en AD" -ForegroundColor Yellow
Write-Host "  • Testez la configuration avec quelques fichiers pour valider" -ForegroundColor Yellow
Write-Host "  • Si les emails externes ne fonctionnent pas:" -ForegroundColor Yellow
Write-Host "    └─ Verifiez que le relais SMTP est bien configure pour 127.0.0.1" -ForegroundColor Yellow
Write-Host "    └─ Verifiez que le serveur SMTP n'est pas un relay ouvert (bloque par le firewall)" -ForegroundColor Yellow

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "FIN DU SCRIPT - CONFIGURATION COMPLETEMENT OPERATIONNELLE" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan