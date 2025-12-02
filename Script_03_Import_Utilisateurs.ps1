# SCRIPT 03 : Import Utilisateurs AVEC STRUCTURE AD CORRECTE
# Fichier: 03-Import-Utilisateurs-Final.ps1
# PowerShell 5.1 COMPATIBLE
# Hierarchie correcte : Categorie > Sous-departement

$CSVPath = "C:\users\Administrateur\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT DES UTILISATEURS - HIERARCHIE CORRECTE" -ForegroundColor Cyan
Write-Host "Domaine: Belgique.lan" -ForegroundColor Cyan
Write-Host "Horaires: Std 6h-18h (M-F) | IT 24h/24" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $CSVPath)) {
    Write-Host "ERREUR: Fichier CSV non trouve!" -ForegroundColor Red
    Break
}

# --- [1] Lecture CSV ---
Write-Host "`n[1/5] Lecture du CSV..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8
Write-Host "OK: $($Users.Count) utilisateurs a importer" -ForegroundColor Green

# --- [2] Definition structure OUs HIERARCHIQUE ---
Write-Host "`n[2/5] Creation de la structure hierarchique..." -ForegroundColor Yellow

# Mapping exact : Categorie > Sous-departement
$OUStructure = @{
    "Direction"           = @()  # Aucun sous-dept, pas d'utilisateurs
    "Technique"           = @("Achat", "Techniciens")
    "Finances"            = @("Comptabilité", "Investissements")
    "Informatique"        = @("Développement", "HotLine", "Systèmes")
    "Ressources humaines" = @("Gestion du personnel", "Recrutement")
    "R&D"                 = @("Recherche", "Testing")
    "Commerciaux"         = @("Sédentaires", "Technico")
    "Marketting"          = @("Site1", "Site2", "Site3", "Site4")
}

# Creer OUs Categories (niveau 1)
foreach ($Category in $OUStructure.Keys) {
    $CategoryOUPath = "OU=$Category,DC=Belgique,DC=lan"
    
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Category'" -SearchBase "DC=Belgique,DC=lan" -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $Category -Path "DC=Belgique,DC=lan" -Confirm:$false
            Write-Host "OK: OU categorie creee: $Category" -ForegroundColor Green
            Set-ADOrganizationalUnit -Identity $CategoryOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
        } else {
            Write-Host "OK: OU categorie existe: $Category" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERREUR creation OU $Category: $_" -ForegroundColor Red
    }
}

# Creer OUs Sous-departements (niveau 2)
foreach ($Category in $OUStructure.Keys) {
    $SubDepts = $OUStructure[$Category]
    $CategoryOUPath = "OU=$Category,DC=Belgique,DC=lan"
    
    foreach ($SubDept in $SubDepts) {
        $SubOUPath = "OU=$SubDept,OU=$Category,DC=Belgique,DC=lan"
        
        try {
            # Verifier que le sous-dept n'existe pas
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$SubDept'" -SearchBase $CategoryOUPath -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $SubDept -Path $CategoryOUPath -Confirm:$false
                Write-Host "  OK: OU sous-dept creee: $Category > $SubDept" -ForegroundColor Green
                Set-ADOrganizationalUnit -Identity $SubOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
            } else {
                Write-Host "  OK: OU sous-dept existe: $Category > $SubDept" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  ERREUR creation OU $SubDept: $_" -ForegroundColor Red
        }
    }
}

# --- [3] Mapping CSV > OUs ---
Write-Host "`n[3/5] Mapping utilisateurs vers OUs..." -ForegroundColor Yellow

# Creer mapping dynamique depuis CSV pour retrouver la categorie
$DepartementToOUPath = @{}
foreach ($User in $Users) {
    $CSVDept = $User.Departement.Trim()  # Ex: "Achat/Technique"
    
    if ($CSVDept.Contains("/")) {
        $Parts = $CSVDept.Split("/")
        $SubDept = $Parts[0].Trim()
        $Category = $Parts[1].Trim()
        $OUPath = "OU=$SubDept,OU=$Category,DC=Belgique,DC=lan"
    } else {
        # Fallback si format non standard
        $OUPath = "OU=Default,DC=Belgique,DC=lan"
    }
    
    if (-not $DepartementToOUPath.ContainsKey($CSVDept)) {
        $DepartementToOUPath[$CSVDept] = $OUPath
    }
}

Write-Host "OK: Mapping cree pour $($DepartementToOUPath.Count) departements" -ForegroundColor Green

# --- [4] Creation Users ---
Write-Host "`n[4/5] Creation des utilisateurs..." -ForegroundColor Yellow

$UserCount = 0
$ErrorCount = 0
$UsedAccounts = @{}
$InfoOUs = @("Développement", "HotLine", "Systèmes")  # Sous-depts IT

foreach ($User in $Users) {
    $Prenom = $User.Prenom.Trim()
    $Nom = $User.Nom.Trim()
    $CSVDept = $User.Departement.Trim()
    $Bureau = $User.Bureau.Trim()
    $Fonction = if ($User.PSObject.Properties.Name -contains 'Fonction') { $User.Fonction } else { $User.Description }
    
    # Nettoyage nom compte
    $PrenomClean = ($Prenom -replace '[^a-zA-Z0-9]', '').ToLower()
    $NomClean = ($Nom -replace '[^a-zA-Z0-9]', '').ToLower()
    
    $BaseName = "$PrenomClean.$NomClean"
    if ($BaseName.Length -gt 20) { $BaseName = $BaseName.Substring(0, 20) }
    
    $SamName = $BaseName
    $Suffix = 0
    while ($UsedAccounts.ContainsKey($SamName) -or (Get-ADUser -Filter "SamAccountName -eq '$SamName'" -ErrorAction SilentlyContinue)) {
        $Suffix++
        $SamName = "$BaseName$Suffix"
    }
    $UsedAccounts[$SamName] = $true

    # Retrouver le chemin OU correct
    $OUPath = $DepartementToOUPath[$CSVDept]
    if (-not $OUPath) {
        Write-Host "SKIP: $SamName - Departement '$CSVDept' non mappe" -ForegroundColor Red
        continue
    }

    $Password = ConvertTo-SecureString "P@ssword2025!" -AsPlainText -Force

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$SamName'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "$Prenom $Nom" -GivenName $Prenom -Surname $Nom -SamAccountName $SamName `
                -UserPrincipalName "$SamName@Belgique.lan" -DisplayName "$Prenom $Nom" -Title $Fonction `
                -Department $CSVDept -Office $Bureau -Path $OUPath -AccountPassword $Password `
                -Enabled $true -ChangePasswordAtLogon $true -Confirm:$false
            
            Write-Host "OK: $SamName ($CSVDept) -> $Bureau" -ForegroundColor Green
            $UserCount++
        }
    } catch {
        Write-Host "ERREUR: $SamName - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

# --- [5] Application Horaires (NET USER) ---
Write-Host "`n[5/5] Application des horaires (NET USER)..." -ForegroundColor Yellow

$StdApplied = 0
$ITApplied = 0
$Failed = 0
$AllUsers = Get-ADUser -Filter "Enabled -eq 'True'" -SearchBase "DC=Belgique,DC=lan" | Where-Object { $_.Enabled -eq $true }

foreach ($User in $AllUsers) {
    if ($User.SamAccountName -in @("Administrator", "Guest", "krbtgt")) { continue }
    
    # Recuperer le sous-dept depuis OU
    $OU = $User.DistinguishedName
    $OUParts = $OU -split "," | Where-Object { $_ -like "OU=*" }
    $SubDept = ($OUParts[0] -replace "OU=", "").Trim()
    
    $SamName = $User.SamAccountName
    $IsIT = $InfoOUs -contains $SubDept

    if ($IsIT) {
        $Cmd = "net user $SamName /times:all /domain"
        $Type = "IT (24h)"
    } else {
        $Cmd = "net user $SamName /times:M-F,06:00-18:00 /domain"
        $Type = "Std (6-18h)"
    }

    Invoke-Expression $Cmd | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: $SamName -> $Type" -ForegroundColor Green
        if ($IsIT) { $ITApplied++ } else { $StdApplied++ }
    } else {
        Write-Host "ERREUR: $SamName (Code $LASTEXITCODE)" -ForegroundColor Red
        $Failed++
    }
}

# --- BILAN ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "IMPORT TERMINE" -ForegroundColor Green
Write-Host "Utilisateurs: $UserCount | Erreurs: $ErrorCount" -ForegroundColor Green
Write-Host "Horaires: Std=$StdApplied | IT=$ITApplied | Echecs=$Failed" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
