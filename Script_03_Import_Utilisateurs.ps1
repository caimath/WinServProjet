# SCRIPT 03 : Import Utilisateurs - POWERSHI LL 5.1 COMPATIBLE
# Fichier: 03-Import-Utilisateurs.ps1

$CSVPath = "C:\users\Administrateur\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT DES UTILISATEURS" -ForegroundColor Cyan
Write-Host "Domaine: Belgique.lan" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $CSVPath)) {
    Write-Host "ERREUR: Fichier CSV non trouve!" -ForegroundColor Red
    Break
}

Write-Host "`n[1/3] Lecture du CSV..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8

Write-Host "OK: $($Users.Count) utilisateurs a importer" -ForegroundColor Green

Write-Host "`n[2/3] Creation des OUs par departement..." -ForegroundColor Yellow

$OUs = $Users.Departement | Select-Object -Unique

foreach ($OU in $OUs) {
    if ([string]::IsNullOrWhiteSpace($OU)) { continue }
    
    $OU = $OU.Trim()
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
$UsedAccounts = @{}

foreach ($User in $Users) {
    $Prenom = $User.Prenom.Trim()
    $Nom = $User.Nom.Trim()
    $Departement = $User.Departement.Trim()
    $Fonction = if ($User.PSObject.Properties.Name -contains 'Fonction') { $User.Fonction } else { $User.Description }
    
    # Traiter les prenoms composes (Jean-Pierre -> jeanPierre)
    $PrenomParts = @($Prenom -split '[^a-zA-Z]' | Where-Object { $_ -ne '' })
    
    if ($PrenomParts.Count -gt 1) {
        $PrenomClean = $PrenomParts[0].ToLower()
        for ($i = 1; $i -lt $PrenomParts.Count; $i++) {
            $PrenomClean += $PrenomParts[$i].Substring(0,1).ToUpper() + $PrenomParts[$i].Substring(1).ToLower()
        }
    } else {
        $PrenomClean = ($Prenom -replace '[^a-zA-Z0-9]', '').ToLower()
    }
    
    $NomClean = ($Nom -replace '[^a-zA-Z0-9]', '').ToLower()
    
    # Construire le compte de base
    $BaseAccountName = "$PrenomClean.$NomClean"
    if ($BaseAccountName.Length -gt 20) {
        $InitialPrenom = $PrenomClean.Substring(0, 1)
        $BaseAccountName = "$InitialPrenom.$NomClean"
    }
    if ($BaseAccountName.Length -gt 20) {
        $BaseAccountName = $BaseAccountName.Substring(0, 20)
    }
    
    # Compter les occurrences du meme prenom.nom dans le CSV
    $CountInCSV = 0
    foreach ($CheckUser in $Users) {
        $CheckPrenom = $CheckUser.Prenom.Trim()
        $CheckNom = $CheckUser.Nom.Trim()
        
        $CheckPrenomParts = @($CheckPrenom -split '[^a-zA-Z]' | Where-Object { $_ -ne '' })
        if ($CheckPrenomParts.Count -gt 1) {
            $CheckPrenomClean = $CheckPrenomParts[0].ToLower()
            for ($j = 1; $j -lt $CheckPrenomParts.Count; $j++) {
                $CheckPrenomClean += $CheckPrenomParts[$j].Substring(0,1).ToUpper() + $CheckPrenomParts[$j].Substring(1).ToLower()
            }
        } else {
            $CheckPrenomClean = ($CheckPrenom -replace '[^a-zA-Z0-9]', '').ToLower()
        }
        
        $CheckNomClean = ($CheckNom -replace '[^a-zA-Z0-9]', '').ToLower()
        $CheckBase = "$CheckPrenomClean.$CheckNomClean"
        if ($CheckBase.Length -gt 20) {
            $CheckBase = $CheckBase.Substring(0, 1) + '.' + $CheckNomClean
        }
        if ($CheckBase.Length -gt 20) {
            $CheckBase = $CheckBase.Substring(0, 20)
        }
        
        if ($CheckBase -eq $BaseAccountName) {
            $CountInCSV++
        }
    }
    
    # Si doublon, forcer initial.nom
    if ($CountInCSV -gt 1) {
        $BaseAccountName = "$($PrenomClean.Substring(0, 1)).$NomClean"
        if ($BaseAccountName.Length -gt 20) {
            $BaseAccountName = $BaseAccountName.Substring(0, 20)
        }
    }
    
    # Gerer les doublons deja crees
    $SamAccountName = $BaseAccountName
    $Suffix = 0
    while ($UsedAccounts.ContainsKey($SamAccountName)) {
        $Suffix++
        $SamAccountName = "$BaseAccountName.$Suffix"
        if ($SamAccountName.Length -gt 20) {
            $SamAccountName = $SamAccountName.Substring(0, 20)
        }
    }
    
    $UsedAccounts[$SamAccountName] = $true
    
    $UPN = "$SamAccountName@Belgique.lan"
    $Password = ConvertTo-SecureString "P@ssword2025!" -AsPlainText -Force
    $OUPath = "OU=$Departement,DC=Belgique,DC=lan"
    
    try {
        if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
            Write-Host "SKIP: $SamAccountName existe deja" -ForegroundColor Gray
            continue
        }

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
