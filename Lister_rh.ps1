# ============================================================================
# Script : List-RH-Users.ps1
# Description : Liste les utilisateurs de l'UO "Ressources humaines" dans AD
# Auteur : Administrateur IT
# Date : 2025-12-04
# Domaine : Belgique.lan
# ============================================================================
# Ce script doit être signé numériquement par un administrateur autorisé
# ============================================================================

#Requires -Version 5.1
#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

Import-Module ActiveDirectory

# ============================================================================
# CONFIGURATION - ADAPTER LE DN SELON VOTRE STRUCTURE AD
# ============================================================================

$ErrorActionPreference = "Continue"
$VerbosePreference = "SilentlyContinue"

# DN de l'UO "Ressources Humaines" dans Belgique.lan
# Option 1 : Si RH est directement sous le domaine
$ouRH = "OU=Ressources humaines,DC=Belgique,DC=lan"

# Option 2 : Si RH est imbriquée (décommenter si nécessaire)
# $ouRH = "OU=Ressources Humaines,OU=Direction,DC=Belgique,DC=lan"

# ============================================================================
# VARIABLES
# ============================================================================

$allUsers = @()
$totalCount = 0
$successCount = 0
$errorCount = 0
$timestampLog = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logPath = "C:\Logs\RH-Users_$timestampLog.log"

# ============================================================================
# FONCTIONS
# ============================================================================

function Write-LogEntry {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    Add-Content -Path $logPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Get-RHUsersFromOU {
    param(
        [string]$OUPath
    )
    
    $users = @()
    
    try {
        # Vérification que l'UO existe
        $ou = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
        Write-LogEntry "✓ UO trouvée : $($ou.Name)" "SUCCESS"
        
        # Récupération de tous les utilisateurs de l'UO et ses sous-OUs
        $adUsers = Get-ADUser -Filter "*" -SearchBase $OUPath -SearchScope Subtree `
            -Properties DisplayName, SamAccountName, EmailAddress, `
            DistinguishedName, Enabled, LastLogonDate, Department, Description, Office, Manager `
            -ErrorAction Stop
        
        if ($adUsers) {
            $userCount = @($adUsers).Count
            Write-LogEntry "Total utilisateurs trouvés dans l'UO : $userCount" "INFO"
            
            foreach ($user in $adUsers) {
                try {
                    $userInfo = [PSCustomObject]@{
                        DisplayName       = $user.DisplayName
                        SamAccountName    = $user.SamAccountName
                        EmailAddress      = $user.EmailAddress
                        DistinguishedName = $user.DistinguishedName
                        Department        = $user.Department
                        Description       = $user.Description
                        Office            = $user.Office
                        Manager           = $user.Manager
                        Enabled           = $user.Enabled
                        LastLogonDate     = $user.LastLogonDate
                        OUPath            = $OUPath
                    }
                    
                    $users += $userInfo
                    
                    $status = if($user.Enabled){'Actif'}else{'Inactif'}
                    Write-LogEntry "  ✓ $($user.DisplayName) ($($user.SamAccountName)) - $($user.Description) - [$status]" "INFO"
                    $script:successCount++
                }
                catch {
                    Write-LogEntry "  ✗ Erreur lors du traitement de $($user.SamAccountName) : $_" "ERROR"
                    $script:errorCount++
                }
            }
        }
        else {
            Write-LogEntry "  ⚠ Aucun utilisateur trouvé dans l'UO" "WARNING"
        }
    }
    catch {
        Write-LogEntry "✗ Erreur : L'UO '$OUPath' n'existe pas ou n'est pas accessible" "ERROR"
        Write-LogEntry "  Détail : $_" "ERROR"
        Write-LogEntry "  Conseil : Vérifiez le DN de l'UO avec : Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName" "INFO"
        $script:errorCount++
    }
    
    return $users
}

function Find-RHOrganizationalUnit {
    Write-LogEntry "Recherche automatique de l'UO RH..." "INFO"
    Write-Host ""
    
    try {
        # Rechercher toutes les OUs contenant "RH" ou "Ressources"
        $ous = Get-ADOrganizationalUnit -Filter "Name -like '*RH*' -or Name -like '*Ressources*'" `
            -SearchBase "DC=Belgique,DC=lan" -SearchScope Subtree -ErrorAction Stop
        
        if ($ous) {
            Write-LogEntry "OUs trouvées correspondant à 'RH' ou 'Ressources' :" "INFO"
            $ous | ForEach-Object {
                Write-LogEntry "  - $($_.Name) : $($_.DistinguishedName)" "INFO"
            }
            return $ous[0].DistinguishedName
        }
        else {
            Write-LogEntry "Aucune OU trouvée avec 'RH' ou 'Ressources'" "WARNING"
        }
    }
    catch {
        Write-LogEntry "Erreur lors de la recherche : $_" "ERROR"
    }
    
    return $null
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host ""
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"
Write-LogEntry "DEBUT : Liste des utilisateurs RH depuis Active Directory" "INFO"
Write-LogEntry "Domaine : Belgique.lan" "INFO"
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"
Write-Host ""

# Création du répertoire de logs s'il n'existe pas
if (-not (Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force -ErrorAction SilentlyContinue | Out-Null
}

# Vérifier si l'UO existe
$testOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouRH'" -ErrorAction SilentlyContinue

if (-not $testOU) {
    Write-LogEntry "⚠ L'UO spécifiée n'a pas été trouvée" "WARNING"
    Write-Host ""
    
    # Recherche automatique
    $foundOU = Find-RHOrganizationalUnit
    
    if ($foundOU) {
        Write-Host ""
        Write-LogEntry "Utilisation de l'UO trouvée : $foundOU" "SUCCESS"
        $ouRH = $foundOU
    }
    else {
        Write-Host ""
        Write-LogEntry "ERREUR : Impossible de trouver l'UO RH. Exécution annulée." "ERROR"
        Write-Host ""
        Write-LogEntry "Actions suggérées :" "INFO"
        Write-LogEntry "  1. Exécuter cette commande pour afficher toutes les OUs :" "INFO"
        Write-LogEntry "     Get-ADOrganizationalUnit -Filter * -SearchBase 'DC=Belgique,DC=lan' | Select-Object Name, DistinguishedName" "INFO"
        Write-LogEntry "  2. Adapter le DN dans le script (variable \$ouRH)" "INFO"
        Write-LogEntry "" "INFO"
        exit 1
    }
}

# ============================================================================
# RÉCUPÉRATION DES UTILISATEURS RH
# ============================================================================

Write-LogEntry "Traitement de l'UO RH : $ouRH" "INFO"
Write-Host ""

$usersFromOU = Get-RHUsersFromOU -OUPath $ouRH

if ($usersFromOU) {
    $allUsers = $usersFromOU
    $script:totalCount = @($usersFromOU).Count
}

# ============================================================================
# RAPPORT FINAL
# ============================================================================

Write-Host ""
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"
Write-LogEntry "RAPPORT FINAL" "INFO"
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"

Write-LogEntry "Total général : $totalCount utilisateur(s) RH" "INFO"
Write-LogEntry "Utilisateurs traités avec succès : $successCount" "SUCCESS"
Write-LogEntry "Erreurs rencontrées : $errorCount" $(if ($errorCount -gt 0) { "WARNING" } else { "INFO" })

# Export en CSV
if ($allUsers.Count -gt 0) {
    $csvPath = "C:\Logs\RH-Users_Export_$timestampLog.csv"
    $allUsers | Export-Csv -Path $csvPath -Encoding UTF8 -NoTypeInformation -Delimiter ";" -ErrorAction SilentlyContinue
    Write-LogEntry "✓ Export CSV : $csvPath" "SUCCESS"
    Write-Host ""
    Write-Host "Aperçu de l'export :" -ForegroundColor Cyan
    $allUsers | Format-Table -Property DisplayName, SamAccountName, Description, Office -AutoSize | Out-Host
}
else {
    Write-LogEntry "Aucun utilisateur à exporter" "WARNING"
}

# Affichage du chemin du log
Write-Host ""
Write-LogEntry "Fichier log : $logPath" "INFO"

Write-Host ""
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"
Write-LogEntry "FIN DU SCRIPT" "INFO"
Write-LogEntry "═════════════════════════════════════════════════════════" "INFO"
Write-Host ""

exit $errorCount
