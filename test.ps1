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
$UsedAccounts = @()

foreach ($User in $Users) {
    $Prenom = $User.Prenom.Trim()
    $Nom = $User.Nom.Trim()
    $Departement = $User.Departement
    $Fonction = $User.Fonction
    
    # Nettoyer les caracteres speciaux
    $PrenomClean = $Prenom -replace "[^a-zA-Z0-9]", ""
    $NomClean = $Nom -replace "[^a-zA-Z0-9]", ""
    
    # Format par defaut: prenom.nom (complet)
    $BaseAccountName = "$PrenomClean.$NomClean".ToLower()
    
    # Si trop long (>20 chars), utiliser initial.nom
    if ($BaseAccountName.Length -gt 20) {
        $InitialPrenom = $PrenomClean.Substring(0, 1).ToLower()
        $BaseAccountName = "$InitialPrenom.$NomClean".ToLower()
    }
    
    # Si encore trop long, couper le nom
    if ($BaseAccountName.Length -gt 20) {
        $BaseAccountName = $BaseAccountName.Substring(0, 20)
    }
    
    # Gerer les doublons
    $SamAccountName = $BaseAccountName
    $Counter = 1
    
    while ($UsedAccounts -contains $SamAccountName) {
        # Si doublon, utiliser initial.nom + numero
        $InitialPrenom = $PrenomClean.Substring(0, 1).ToLower()
        $SamAccountName = "$InitialPrenom.$NomClean$Counter".ToLower()
        
        # Si ca depasse 20, couper et ajouter le numero
        if ($SamAccountName.Length -gt 20) {
            $SamAccountName = "$($SamAccountName.Substring(0, 18))$Counter"
        }
        
        $Counter++
    }
    
    $UsedAccounts += $SamAccountName
    
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
