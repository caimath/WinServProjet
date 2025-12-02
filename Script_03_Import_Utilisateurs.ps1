# SCRIPT 03 : Import Utilisateurs COMPLETE - SANS SKIP
# Tous les utilisateurs sont créés (Direction ou Hiérarchie)

$CSVPath = "C:\users\Administrator\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT UTILISATEURS + STRUCTURE + HORAIRES" -ForegroundColor Cyan
Write-Host "Domaine: Belgique.lan" -ForegroundColor Cyan
Write-Host "Horaires: Std 6h-18h (Lun-Ven) | IT 24h/24" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $CSVPath)) {
    Write-Host "ERREUR: Fichier CSV non trouve!" -ForegroundColor Red
    Break
}

# --- [1] Lecture CSV ---
Write-Host "`n[1/5] Lecture du CSV..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8
Write-Host "OK: $($Users.Count) utilisateurs a importer" -ForegroundColor Green

# --- [2] Analyse Structure OUs ---
Write-Host "`n[2/5] Analyse et Creation de la structure OUs..." -ForegroundColor Yellow

$OUStructure = @{}
$SingleOUs = @()

foreach ($User in $Users) {
    $Dept = $User.Departement.Trim()
    if ($Dept) {
        if ($Dept.Contains("/")) {
            $Parts = $Dept.Split("/")
            $SubDept = $Parts[0].Trim()
            $Category = $Parts[1].Trim()
            
            if (-not $OUStructure.ContainsKey($Category)) {
                $OUStructure[$Category] = @()
            }
            if ($OUStructure[$Category] -notcontains $SubDept) {
                $OUStructure[$Category] += $SubDept
            }
        } else {
            if ($SingleOUs -notcontains $Dept) {
                $SingleOUs += $Dept
            }
        }
    }
}

# 2a. Création OUs SIMPLES
foreach ($OUName in $SingleOUs) {
    $OUPath = "OU=${OUName},DC=Belgique,DC=lan"
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '${OUName}'" -SearchBase "DC=Belgique,DC=lan" -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $OUName -Path "DC=Belgique,DC=lan" -Confirm:$false
            Write-Host "OK: OU simple creee: ${OUName}" -ForegroundColor Green
            Set-ADOrganizationalUnit -Identity $OUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
        } else {
            Write-Host "OK: OU simple existe: ${OUName}" -ForegroundColor Gray
        }
    } catch { 
        Write-Host "ERREUR OU ${OUName}: $_" -ForegroundColor Red 
    }
}

# 2b. Création OUs HIERARCHIQUES
foreach ($Category in $OUStructure.Keys) {
    $CategoryOUPath = "OU=${Category},DC=Belgique,DC=lan"
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '${Category}'" -SearchBase "DC=Belgique,DC=lan" -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $Category -Path "DC=Belgique,DC=lan" -Confirm:$false
            Write-Host "OK: OU categorie creee: ${Category}" -ForegroundColor Green
            Set-ADOrganizationalUnit -Identity $CategoryOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
        }
    } catch { 
        Write-Host "ERREUR OU ${Category}: $_" -ForegroundColor Red 
    }
    
    foreach ($SubDept in $OUStructure[$Category]) {
        $SubOUPath = "OU=${SubDept},OU=${Category},DC=Belgique,DC=lan"
        try {
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '${SubDept}'" -SearchBase $CategoryOUPath -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $SubDept -Path $CategoryOUPath -Confirm:$false
                Write-Host "  OK: OU sous-dept creee: ${Category} > ${SubDept}" -ForegroundColor Green
                Set-ADOrganizationalUnit -Identity $SubOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
            }
        } catch { 
            Write-Host "  ERREUR OU ${SubDept}: $_" -ForegroundColor Red 
        }
    }
}

# --- [3] Creation Users ---
Write-Host "`n[3/5] Creation des utilisateurs..." -ForegroundColor Yellow

$UserCount = 0
$ErrorCount = 0
$UsedAccounts = @{}

foreach ($User in $Users) {
    $Prenom = $User.Prenom.Trim()
    $Nom = $User.Nom.Trim()
    $Departement = $User.Departement.Trim()
    $Bureau = $User.Bureau.Trim()
    $Fonction = if ($User.PSObject.Properties.Name -contains 'Fonction') { $User.Fonction.Trim() } else { $User.Description.Trim() }
    
    # Génération SamAccountName unique
    $PrenomClean = ($Prenom -replace '[^a-zA-Z0-9]', '').ToLower()
    $NomClean = ($Nom -replace '[^a-zA-Z0-9]', '').ToLower()
    
    $BaseName = "$PrenomClean.$NomClean"
    if ($BaseName.Length -gt 20) { $BaseName = $BaseName.Substring(0, 20) }
    
    $SamName = $BaseName
    $Suffix = 0
    while ($UsedAccounts.ContainsKey($SamName) -or (Get-ADUser -Filter "SamAccountName -eq '${SamName}'" -ErrorAction SilentlyContinue)) {
        $Suffix++
        $SamName = "$BaseName$Suffix"
    }
    $UsedAccounts[$SamName] = $true

    # Détermination du chemin OU (PAS DE SKIP - Support Direction ET Hiérarchie)
    if ($Departement.Contains("/")) {
        $Parts = $Departement.Split("/")
        $SubDept = $Parts[0].Trim()
        $Category = $Parts[1].Trim()
        $OUPath = "OU=${SubDept},OU=${Category},DC=Belgique,DC=lan"
    } else {
        # Cas Direction OU autre département simple (PAS DE SLASH)
        $OUPath = "OU=${Departement},DC=Belgique,DC=lan"
    }

    $Password = ConvertTo-SecureString "P@ssword2025!" -AsPlainText -Force

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '${SamName}'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "$Prenom $Nom" -GivenName $Prenom -Surname $Nom -SamAccountName $SamName `
                -UserPrincipalName "$SamName@Belgique.lan" -DisplayName "$Prenom $Nom" -Title $Fonction `
                -Department $Departement -Office $Bureau -Path $OUPath -AccountPassword $Password `
                -Enabled $true -ChangePasswordAtLogon $true -Confirm:$false
            
            Write-Host "OK: $SamName ($Departement) -> $Bureau" -ForegroundColor Green
            $UserCount++
        } else {
            Write-Host "SKIP: $SamName existe deja" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERREUR: $SamName ($Departement) - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

# --- [4] Application Horaires (NET USER) ---
Write-Host "`n[4/5] Application des horaires (NET USER)..." -ForegroundColor Yellow

$StdApplied = 0
$ITApplied = 0
$Failed = 0

$ITDepts = @("HotLine", "Systemes", "Developpement", "Systèmes", "Développement")

$AllUsers = Get-ADUser -Filter "Enabled -eq `$true" -SearchBase "DC=Belgique,DC=lan" -Properties DistinguishedName | `
    Where-Object { $_.SamAccountName -notmatch "^(Administrator|Guest|krbtgt)" }

foreach ($User in $AllUsers) {
    $SamName = $User.SamAccountName
    $DN = $User.DistinguishedName
    $IsIT = $false
    
    if ($DN -match "OU=([^,]+),OU=") {
        $SubDept = $Matches[1]
        if ($ITDepts -contains $SubDept) { $IsIT = $true }
    }

    if ($IsIT) {
        $Cmd = "net user $SamName /times:all"
        Invoke-Expression $Cmd | Out-Null
        if ($LASTEXITCODE -eq 0) { 
            Write-Host "OK: $SamName -> IT (24h)" -ForegroundColor Cyan
            $ITApplied++ 
        } else { $Failed++ }
    } else {
        $Cmd = "net user $SamName /times:M-F,6am-6pm"
        Invoke-Expression $Cmd | Out-Null
        if ($LASTEXITCODE -eq 0) { 
            Write-Host "OK: $SamName -> STD (M-F 6-18h)" -ForegroundColor Green
            $StdApplied++ 
        } else { $Failed++ }
    }
}

# --- [5] Bilan ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BILAN IMPORT & CONFIGURATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Utilisateurs crees: $UserCount / $($Users.Count)" -ForegroundColor Green
Write-Host "Erreurs creation: $ErrorCount" -ForegroundColor $(if($ErrorCount -gt 0){"Red"}else{"Green"})
Write-Host "`nHoraires configures:" -ForegroundColor Green
Write-Host "  - Standard (M-F 6-18h): $StdApplied" -ForegroundColor Green
Write-Host "  - IT (24h/24): $ITApplied" -ForegroundColor Cyan
Write-Host "  - Echecs: $Failed" -ForegroundColor $(if($Failed -gt 0){"Red"}else{"Green"})
Write-Host "========================================" -ForegroundColor Green
