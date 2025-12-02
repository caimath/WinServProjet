# SCRIPT 03 : Import Utilisateurs - VERSION SIMPLE ET ROBUSTE
# Fichier: 03-Import-Utilisateurs.ps1

# Chemin du CSV
$CSVPath = "C:\users\Administrateur\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT DES UTILISATEURS" -ForegroundColor Cyan
Write-Host "Domaine: Belgique.lan" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verifier que le CSV existe
if (-not (Test-Path $CSVPath)) {
    Write-Host "ERREUR: Fichier CSV non trouve!" -ForegroundColor Red
    Write-Host "Cherche: $CSVPath" -ForegroundColor Red
    Break
}

Write-Host "`n[1/3] Lecture du CSV..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";"

Write-Host "OK: $($Users.Count) utilisateurs a importer" -ForegroundColor Green

Write-Host "`n[2/3] Creation des OUs par departement..." -ForegroundColor Yellow

$OUs = $Users.Departement | Select-Object -Unique

foreach ($OU in $OUs) {
    $OUPath = "OU=$OU,DC=Belgique,DC=lan"
    
    try {
        $CheckOU = Get-ADOrganizationalUnit -Filter "Name -eq '$OU'" -ErrorAction SilentlyContinue
        
        if (-not $CheckOU) {
            New-ADOrganizationalUnit -Name $OU -Path "DC=Belgique,DC=lan" -Confirm:$false
            Write-Host "OK: OU creee: $OU" -ForegroundColor Green
        } else {
            Write-Host "OK: OU existante: $OU" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERREUR creation OU $OU : $_" -ForegroundColor Red
    }
}

Write-Host "`n[3/3] Creation des utilisateurs..." -ForegroundColor Yellow

$UserCount = 0
$ErrorCount = 0

foreach ($User in $Users) {
    $Prenom = $User.Prenom
    $Nom = $User.Nom
    $Departement = $User.Departement
    $Fonction = $User.Fonction
    
    # Creer SamAccountName (max 20 chars, pas d'espaces)
    $SamAccountName = "$($Prenom.Substring(0,1))$Nom".ToLower() -replace " ", "" -replace "[^a-z0-9]", ""
    
    # Creer le UPN
    $UPN = "$SamAccountName@Belgique.lan"
    
    # Creer mot de passe temporaire
    $Password = ConvertTo-SecureString "P@ssword2025!" -AsPlainText -Force
    
    # Path OU
    $OUPath = "OU=$Departement,DC=Belgique,DC=lan"
    
    try {
        # Creer l'utilisateur
        New-ADUser -Name "$Prenom $Nom" `
            -GivenName $Prenom `
            -Surname $Nom `
            -SamAccountName $SamAccountName `
            -UserPrincipalName $UPN `
            -DisplayName "$Prenom $Nom" `
            -Title $Fonction `
            -Department $Departement `
            -Path $OUPath `
            -AccountPassword $Password `
            -Enabled $true `
            -ChangePasswordAtLogon $true `
            -Confirm:$false
        
        Write-Host "OK: $SamAccountName ($Prenom $Nom)" -ForegroundColor Green
        $UserCount++
        
    } catch {
        Write-Host "ERREUR: $SamAccountName - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "OK: IMPORT TERMINE" -ForegroundColor Green
Write-Host "Utilisateurs crees: $UserCount" -ForegroundColor Green
Write-Host "Erreurs: $ErrorCount" -ForegroundColor $(if ($ErrorCount -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nProchaines etapes:" -ForegroundColor Cyan
Write-Host "  1. Verifier dans Active Directory Users and Computers" -ForegroundColor Gray
Write-Host "  2. Les utilisateurs doivent changer leur password a la prochaine connexion" -ForegroundColor Gray
Write-Host "  3. Verifier les permissions sur les partages reseau" -ForegroundColor Gray
