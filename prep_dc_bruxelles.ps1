# ========================================
# SCRIPT PREPARATION DC-BRUXELLES
# Vérifie et configure tout ce qui est nécessaire
# pour la promotion du DC Replica NAMUR
# ========================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PREPARATION DC-BRUXELLES" -ForegroundColor Cyan
Write-Host "Installation/Configuration ADWS + Site NAMUR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ========================================
# FONCTION: Afficher message coloré
# ========================================
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("OK", "ERROR", "WARNING", "INFO", "SECTION")]$Type = "INFO"
    )
    
    $Colors = @{
        "OK"      = "Green"
        "ERROR"   = "Red"
        "WARNING" = "Yellow"
        "INFO"    = "Cyan"
        "SECTION" = "Cyan"
    }
    
    $Prefix = @{
        "OK"      = "[OK]"
        "ERROR"   = "[ERROR]"
        "WARNING" = "[WARNING]"
        "INFO"    = "[*]"
        "SECTION" = "===="
    }
    
    Write-Host "$($Prefix[$Type]) $Message" -ForegroundColor $Colors[$Type]
}

# ========================================
# SECTION 0: VERIFICATIONS ADMIN
# ========================================
Write-Status "VERIFICATION PERMISSIONS" "SECTION"
Write-Host ""

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $IsAdmin) {
    Write-Status "ERREUR: Ce script doit etre execute en tant qu'Administrateur !" "ERROR"
    Write-Status "Relance PowerShell en tant qu'Administrateur" "ERROR"
    exit
}

Write-Status "Permissions Administrateur confirmees" "OK"
Write-Host ""

# ========================================
# SECTION 1: VERIFIER ET INSTALLER ADWS
# ========================================
Write-Status "VERIFICATION/INSTALLATION DU SERVICE ADWS" "SECTION"
Write-Host ""

# 1.1 Charger les modules necessaires
Write-Status "Chargement des modules..." "INFO"
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Status "Module ActiveDirectory charge" "OK"
} catch {
    Write-Status "ERREUR: Module ActiveDirectory non disponible" "ERROR"
    Write-Status "Ce serveur n'est peut-etre pas un Domain Controller !" "ERROR"
    exit
}
Write-Host ""

# 1.2 Verifier que c'est un DC
Write-Status "Verification que c'est un Domain Controller..." "INFO"
try {
    $DCCheck = Get-ADDomainController -Identity (hostname) -ErrorAction SilentlyContinue
    
    if ($DCCheck) {
        Write-Status "Domain Controller confirme: $(hostname)" "OK"
    } else {
        Write-Status "ERREUR: Pas un Domain Controller !" "ERROR"
        exit
    }
} catch {
    Write-Status "ERREUR: Impossible de verifier le DC" "ERROR"
    exit
}
Write-Host ""

# 1.3 Verifier l'etat du service ADWS
Write-Status "Verification de l'etat du service ADWS..." "INFO"
try {
    $ADWSService = Get-Service -Name ADWS -ErrorAction SilentlyContinue
    
    if ($ADWSService) {
        Write-Status "Service ADWS trouve" "OK"
        Write-Host "  Name: $($ADWSService.Name)" -ForegroundColor Gray
        Write-Host "  Status: $($ADWSService.Status)" -ForegroundColor Gray
        Write-Host "  StartType: $($ADWSService.StartType)" -ForegroundColor Gray
        
        # 1.4 Si le service n'est pas en cours d'exécution, le démarrer
        if ($ADWSService.Status -ne "Running") {
            Write-Status "Le service ADWS n'est pas demarree, demarrage..." "WARNING"
            Start-Service -Name ADWS -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Status "Service ADWS demarree" "OK"
        } else {
            Write-Status "Le service ADWS est deja en cours d'execution" "OK"
        }
        
        # 1.5 Verifier que le service est parametre pour demarrage automatique
        if ($ADWSService.StartType -ne "Automatic") {
            Write-Status "Configuration du demarrage automatique..." "INFO"
            Set-Service -Name ADWS -StartupType Automatic -ErrorAction Stop
            Write-Status "Demarrage automatique configure" "OK"
        } else {
            Write-Status "Demarrage automatique deja configure" "OK"
        }
    } else {
        Write-Status "ERREUR: Service ADWS non trouve !" "ERROR"
        Write-Status "Ce serveur n'est peut-etre pas un Domain Controller !" "ERROR"
        exit
    }
} catch {
    Write-Status "ERREUR lors de la gestion du service ADWS: $_" "ERROR"
    exit
}
Write-Host ""

# 1.6 Verifier que le service est bien demarree apres modification
Write-Status "Verification finale du service ADWS..." "INFO"
try {
    $ADWSVerify = Get-Service -Name ADWS -ErrorAction Stop
    
    if ($ADWSVerify.Status -eq "Running") {
        Write-Status "Service ADWS: DEMARREE (RUNNING)" "OK"
    } else {
        Write-Status "ERREUR: Service ADWS n'est pas demarree !" "ERROR"
        Write-Status "Verifie manuellement: Get-Service ADWS" "WARNING"
        exit
    }
} catch {
    Write-Status "ERREUR lors de la verification: $_" "ERROR"
    exit
}
Write-Host ""

# ========================================
# SECTION 2: VERIFIER LE PORT 9389
# ========================================
Write-Status "VERIFICATION DU PORT 9389 (ADWS)" "SECTION"
Write-Host ""

Write-Status "Verification que le port 9389 est en ecoute..." "INFO"
try {
    $NetstatCheck = netstat -ano -ErrorAction SilentlyContinue | Select-String ":9389"
    
    if ($NetstatCheck) {
        Write-Status "Port 9389 en ecoute !" "OK"
        Write-Host "  Connexions sur le port 9389:" -ForegroundColor Gray
        $NetstatCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } else {
        Write-Status "ATTENTION: Port 9389 ne semble pas en ecoute" "WARNING"
        Write-Status "Redemarrage du service ADWS..." "INFO"
        Restart-Service -Name ADWS -Force -ErrorAction Stop
        Start-Sleep -Seconds 3
        
        $NetstatCheck2 = netstat -ano -ErrorAction SilentlyContinue | Select-String ":9389"
        if ($NetstatCheck2) {
            Write-Status "Port 9389 maintenant en ecoute apres redemarrage" "OK"
        } else {
            Write-Status "ERREUR: Port 9389 toujours pas en ecoute apres redemarrage" "ERROR"
            exit
        }
    }
} catch {
    Write-Status "ERREUR lors de la verification du port: $_" "ERROR"
    exit
}
Write-Host ""

# ========================================
# SECTION 3: CREER LE SITE NAMUR
# ========================================
Write-Status "CREATION/VERIFICATION DU SITE NAMUR" "SECTION"
Write-Host ""

Write-Status "Verification que le site NAMUR existe..." "INFO"
try {
    $SiteCheck = Get-ADReplicationSite -Filter { Name -eq "NAMUR" } -ErrorAction SilentlyContinue
    
    if ($SiteCheck) {
        Write-Status "Le site NAMUR existe deja" "OK"
        Write-Host "  Name: $($SiteCheck.Name)" -ForegroundColor Gray
        Write-Host "  DN: $($SiteCheck.DistinguishedName)" -ForegroundColor Gray
    } else {
        Write-Status "Le site NAMUR n'existe pas, creation..." "INFO"
        New-ADReplicationSite -Name "NAMUR" -Confirm:$false -ErrorAction Stop
        Write-Status "Site NAMUR cree" "OK"
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Status "ERREUR lors de la creation du site: $_" "ERROR"
    exit
}
Write-Host ""

# ========================================
# SECTION 4: VERIFICATION FINALE
# ========================================
Write-Status "VERIFICATION FINALE" "SECTION"
Write-Host ""

Write-Status "Liste de tous les sites AD:" "INFO"
try {
    $AllSites = Get-ADReplicationSite -Filter * -ErrorAction Stop
    Write-Host "  Sites trouves:" -ForegroundColor Gray
    $AllSites | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Gray }
    
    if ($AllSites | Where-Object { $_.Name -eq "NAMUR" }) {
        Write-Status "Site NAMUR confirme dans Active Directory" "OK"
    } else {
        Write-Status "ATTENTION: Site NAMUR introuvable !" "WARNING"
    }
} catch {
    Write-Status "ERREUR lors de la lecture des sites: $_" "ERROR"
}
Write-Host ""

# ========================================
# RESUME FINAL
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "PREPARATION DC-BRUXELLES TERMINEE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Status "Resume:" "OK"
Write-Host "  ✅ Service ADWS: DEMARREE + AUTOMATIQUE" -ForegroundColor Green
Write-Host "  ✅ Port 9389: EN ECOUTE" -ForegroundColor Green
Write-Host "  ✅ Site NAMUR: CREE" -ForegroundColor Green
Write-Host ""

Write-Status "Prochaine etape:" "INFO"
Write-Host "  1. Relance le script de promotion sur NAMUR (172.25.60.21)" -ForegroundColor Cyan
Write-Host "  2. Credentials: Belgique\Administrator" -ForegroundColor Cyan
Write-Host "  3. Password: Lpsselcelc*" -ForegroundColor Cyan
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "PRET POUR LA PROMOTION DU DC REPLICA !" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
