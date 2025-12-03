# ════════════════════════════════════════════════════════════════════════════
# SCRIPT FSRM COMPLET - QUOTAS + ALERTES + FILTRAGE
# Dossier racine: C:\Share
# Features: 
#   1. Installation FSRM
#   2. Configuration quotas avec seuils
#   3. Alertes email via Gmail SMTP
#   4. Filtrage fichiers (Office + Images uniquement)
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"

# ===== CONFIGURATION GMAIL SMTP =====
$GmailAccount = "fsrm.belgique@gmail.com"
$GmailAppPassword = "dzlh yqgi sscq lrmm"
$SmtpServer = "smtp.gmail.com"
$SmtpPort = 587
$FromEmail = "fsrm.belgique@gmail.com"
$AdminEmail = "robin.gillard1@std.heh.be"

[System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "CONFIGURATION FSRM COMPLETE - QUOTAS + ALERTES + FILTRAGE" -ForegroundColor Cyan
Write-Host "Domain: $Domain" -ForegroundColor Cyan
Write-Host "Admin: $AdminEmail" -ForegroundColor Cyan
Write-Host "SMTP: $SmtpServer (Port $SmtpPort - TLS)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════════════════════════════
# PARTIE 1 - QUOTAS & ALERTES
# ══════════════════════════════════════════════════════════════════════════════

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

# --- [2] TEST DE CONNECTIVITE SMTP GMAIL ---
Write-Host "`n[2/10] Test de connectivite SMTP Gmail..." -ForegroundColor Yellow

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
    exit
}

# --- [3] DEFINITION DE LA STRUCTURE ---
Write-Host "`n[3/10] Chargement de la structure departements..." -ForegroundColor Yellow

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
Write-Host "`n[4/10] Extraction des emails depuis AD..." -ForegroundColor Yellow

function Get-UserEmailFromAD {
    param([string]$SamAccountName)
    try {
        $AdUser = Get-ADUser -Identity $SamAccountName -Properties Mail -ErrorAction SilentlyContinue
        if ($AdUser -and $AdUser.Mail) {
            return $AdUser.Mail
        }
    } catch { }
    return "$SamAccountName@$Domain"
}

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

    if (-not (Test-Path $Path)) {
        Write-Host "    ⚠️  Dossier inexistant: $Path" -ForegroundColor Yellow
        return
    }

    try {
        Get-FsrmQuota -Path $Path -ErrorAction SilentlyContinue | Remove-FsrmQuota -Confirm:$false -ErrorAction SilentlyContinue
        
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

═══════════════════════════════════════════════════════════════
Script FSRM Automatique - Configuration de Quotas
═══════════════════════════════════════════════════════════════
"@

        $ActionEmail = New-FsrmAction -Type Email `
            -MailTo "$ResponsibleEmail;$AdminEmail" `
            -Subject $EmailSubject `
            -Body $EmailBody

        $EventBody = "ALERTE QUOTA FSRM: '$QuotaName' ($Path) a atteint [Quota Used Percent]%. Responsable: $ResponsibleEmail. Date: [Timestamp]"
        $ActionEvent = New-FsrmAction -Type Event -EventType Warning -Body $EventBody
        
        $Threshold80 = New-FsrmQuotaThreshold -Percentage 80 -Action $ActionEmail
        $Threshold90 = New-FsrmQuotaThreshold -Percentage 90 -Action $ActionEmail, $ActionEvent
        $Threshold100 = New-FsrmQuotaThreshold -Percentage 100 -Action $ActionEmail, $ActionEvent
        
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
Write-Host "`n[5/10] Application des quotas sur toute la structure..." -ForegroundColor Yellow

Write-Host "`n  [A] Quotas DEPARTEMENTS - 500 MB (Hard Limit)..." -ForegroundColor Cyan
foreach ($Category in $Structure.Keys) {
    $CategoryPath = Join-Path -Path $RootPath -ChildPath $Category
    Set-QuotaWithAlerts -Path $CategoryPath -SizeMB 500 -ResponsibleEmail $AdminEmail -QuotaName "DEPT: $Category"
}

Write-Host "`n  [B] Quotas SOUS-DEPARTEMENTS - 100 MB (Hard Limit)..." -ForegroundColor Cyan
foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $SubPath = Join-Path -Path $RootPath -ChildPath $Category | Join-Path -ChildPath $SubDept
        $RespEmail = $EmailCache["$Category|$SubDept"]
        Set-QuotaWithAlerts -Path $SubPath -SizeMB 100 -ResponsibleEmail $RespEmail -QuotaName "SUB-DEPT: $SubDept"
    }
}

Write-Host "`n  [C] Quota COMMUN - 500 MB (Hard Limit)..." -ForegroundColor Cyan
$CommonPath = Join-Path -Path $RootPath -ChildPath "Commun"
Set-QuotaWithAlerts -Path $CommonPath -SizeMB 500 -ResponsibleEmail $AdminEmail -QuotaName "COMMUN: Ressources Partagees"

# --- [7] VERIFICATION FINALE ---
Write-Host "`n[6/10] Verification finale des quotas appliques..." -ForegroundColor Yellow

$AllQuotas = Get-FsrmQuota -ErrorAction SilentlyContinue
Write-Host "`n✅ Nombre total de quotas appliques: $($AllQuotas.Count)" -ForegroundColor Green

foreach ($Quota in $AllQuotas) {
    $SizeMB = $Quota.Size / 1MB
    $Usage = if ($Quota.Usage) { "{0:P0}" -f ($Quota.Usage / $Quota.Size) } else { "0%" }
    Write-Host "  ├─ $($Quota.Path) | Limite: $([math]::Round($SizeMB)) MB | Utilisation: $Usage" -ForegroundColor Gray
}

# ══════════════════════════════════════════════════════════════════════════════
# PARTIE 2 - FILTRAGE FICHIERS (à la fin, après les quotas)
# ══════════════════════════════════════════════════════════════════════════════

Write-Host "`n[7/10] Creation du groupe de fichiers autorises..." -ForegroundColor Yellow

$GroupName = "Autorises_Office_Images"
$ExistingGroup = Get-FsrmFileGroup -Name $GroupName -ErrorAction SilentlyContinue

if (-not $ExistingGroup) {
    $OfficeExt = @(
        "*.doc", "*.docx", "*.dot", "*.dotx",
        "*.xls", "*.xlsx", "*.xlt", "*.xltx",
        "*.ppt", "*.pptx", "*.pot", "*.potx",
        "*.odt", "*.ods", "*.odp",
        "*.rtf", "*.txt", "*.pdf"
    )
    
    $ImageExt = @(
        "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp",
        "*.tiff", "*.tif", "*.webp", "*.svg", "*.ico",
        "*.psd", "*.raw"
    )
    
    $AllowedExt = $OfficeExt + $ImageExt
    
    New-FsrmFileGroup -Name $GroupName -IncludePattern $AllowedExt `
        -Description "Fichiers Office et Images autorises sur C:\Share"
    
    Write-Host "✅ Groupe cree: $GroupName" -ForegroundColor Green
    Write-Host "   Office ($($OfficeExt.Count) ext) + Images ($($ImageExt.Count) ext)" -ForegroundColor Green
} else {
    Write-Host "✅ Groupe existe deja: $GroupName" -ForegroundColor Gray
}

Write-Host "`n[8/10] Application du filtrage sur C:\Share et sous-dossiers..." -ForegroundColor Yellow

$ActionEventLog = New-FsrmAction -Type Event -EventType Warning `
    -Body "FSRM BLOQUE: Tentative de depot d'un fichier non autorise. Extension interdite (Office et Images uniquement). Dossier: [FileScreenPath] | Fichier: [Filename] | User: [SourceFileOwner]"

function Apply-FileScreenRecursive {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return
    }
    
    $Existing = Get-FsrmFileScreen -Path $Path -ErrorAction SilentlyContinue
    
    if (-not $Existing) {
        try {
            New-FsrmFileScreen -Path $Path `
                -ExcludeGroup $GroupName `
                -Notification $ActionEventLog
            Write-Host "  ✓ Filtrage applique: $Path" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Erreur sur $Path : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⊘ Filtrage existe deja: $Path" -ForegroundColor Gray
    }
    
    try {
        $SubFolders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
        foreach ($SubFolder in $SubFolders) {
            Apply-FileScreenRecursive -Path $SubFolder.FullName
        }
    }
    catch { }
}

Apply-FileScreenRecursive -Path $RootPath

# --- BILAN FINAL ---
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CONFIGURATION FSRM COMPLETE ET OPERATIONNELLE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n[9/10] RESUME DES CONFIGURATIONS:" -ForegroundColor Cyan
Write-Host "  📊 QUOTAS: Departements (500MB) + Sous-depts (100MB) + Commun (500MB)" -ForegroundColor Yellow
Write-Host "  📧 ALERTES: 80% (email) → 90% (email+log) → 100% (BLOQUE)" -ForegroundColor Yellow
Write-Host "  📁 FILTRAGE: Office + Images uniquement (tout le reste bloque)" -ForegroundColor Yellow
Write-Host "  📨 EMAIL: Via Gmail SMTP ($SmtpServer)" -ForegroundColor Yellow
Write-Host "  ⚙️  MODE: HARD LIMIT (ecriture bloquee a 100% quota)" -ForegroundColor Yellow

Write-Host "`n[10/10] COMMANDES UTILES:" -ForegroundColor Cyan
Write-Host "  • Voir les quotas: Get-FsrmQuota | Select Path, Size, Usage" -ForegroundColor Gray
Write-Host "  • Voir les filtrages: Get-FsrmFileScreen | Select Path" -ForegroundColor Gray
Write-Host "  • Voir les alertes: Get-EventLog -LogName Application -Source SRMSVC -Newest 20" -ForegroundColor Gray

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Configuration FSRM terminee avec succes! 🚀" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
