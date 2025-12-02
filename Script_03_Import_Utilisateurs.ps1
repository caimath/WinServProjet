# SCRIPT 03 : Import Utilisateurs AVEC BUREAU, HIERARCHIE, PROTECTION ET LOGON HOURS (ANGLAIS)
# Fichier: 03-Import-Utilisateurs-Final.ps1
# PowerShell 5.1 COMPATIBLE

$CSVPath = "C:\users\Administrateur\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT DES UTILISATEURS AVEC BUREAU ET HORAIRES" -ForegroundColor Cyan
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

# --- [2] Structure OUs + Protection ---
Write-Host "`n[2/5] Creation des OUs avec hierarchie et PROTECTION..." -ForegroundColor Yellow

$Departments = @{}
foreach ($User in $Users) {
    $Dept = $User.Departement.Trim()
    if ($Dept -and $Dept.Contains("/")) {
        $Category = $Dept.Split("/")[0].Trim()
        if (-not $Departments.ContainsKey($Category)) { $Departments[$Category] = @() }
        if ($Departments[$Category] -notcontains $Dept) { $Departments[$Category] += $Dept }
    }
}

foreach ($Category in $Departments.Keys) {
    $CategoryOUPath = "OU=$Category,DC=Belgique,DC=lan"
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Category'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $Category -Path "DC=Belgique,DC=lan" -Confirm:$false
            Write-Host "OK: OU categorie creee: $Category" -ForegroundColor Green
            Set-ADOrganizationalUnit -Identity $CategoryOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
        }
    } catch { Write-Host "ERREUR OU $Category: $_" -ForegroundColor Red }
    
    foreach ($Dept in $Departments[$Category]) {
        $DeptOUPath = "OU=$Dept,OU=$Category,DC=Belgique,DC=lan"
        try {
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Dept'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $Dept -Path $CategoryOUPath -Confirm:$false
                Write-Host "OK: OU departement creee: $Dept" -ForegroundColor Green
                Set-ADOrganizationalUnit -Identity $DeptOUPath -ProtectedFromAccidentalDeletion $true -Confirm:$false
            }
        } catch { Write-Host "ERREUR OU $Dept: $_" -ForegroundColor Red }
    }
}

# --- [3] Creation Users ---
Write-Host "`n[3/5] Creation des utilisateurs..." -ForegroundColor Yellow

$UserCount = 0
$ErrorCount = 0
$UsedAccounts = @{}
$InfoOUs = @("HotLine/Informatique", "Systemes/Informatique", "Developpement/Informatique")

foreach ($User in $Users) {
    # Nettoyage et Generation SamAccountName
    $Prenom = $User.Prenom.Trim(); $Nom = $User.Nom.Trim()
    $Departement = $User.Departement.Trim(); $Bureau = $User.Bureau.Trim()
    $Fonction = if ($User.PSObject.Properties.Name -contains 'Fonction') { $User.Fonction } else { $User.Description }
    
    $PrenomClean = ($Prenom -replace '[^a-zA-Z0-9]', '').ToLower() # Simplifié pour robustesse
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

    $OUPath = "OU=$Departement,OU=$($Departement.Split('/')[0]),DC=Belgique,DC=lan"
    $Password = ConvertTo-SecureString "P@ssword2025!" -AsPlainText -Force

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$SamName'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "$Prenom $Nom" -GivenName $Prenom -Surname $Nom -SamAccountName $SamName `
                -UserPrincipalName "$SamName@Belgique.lan" -DisplayName "$Prenom $Nom" -Title $Fonction `
                -Department $Departement -Office $Bureau -Path $OUPath -AccountPassword $Password `
                -Enabled $true -ChangePasswordAtLogon $true -Confirm:$false
            
            Write-Host "OK: $SamName ($Bureau)" -ForegroundColor Green
            $UserCount++
        } else {
            Write-Host "SKIP: $SamName existe" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERREUR: $SamName - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

# --- [4] Application Horaires (NET USER / EN) ---
Write-Host "`n[4/5] Application des horaires (NET USER - ANGLAIS)..." -ForegroundColor Yellow

$StdApplied = 0; $ITApplied = 0; $Failed = 0
$AllUsers = Get-ADUser -Filter * -SearchBase "DC=Belgique,DC=lan" -Properties Department | Where-Object { $_.Enabled -eq $true }

foreach ($User in $AllUsers) {
    if ($User.SamAccountName -in @("Administrator", "Guest", "krbtgt")) { continue }
    
    $SamName = $User.SamAccountName
    $IsIT = $InfoOUs -contains $User.Department

    if ($IsIT) {
        # IT = Tout autorisé (24/24)
        $Cmd = "net user $SamName /times:all /domain"
        $Type = "IT (24h)"
    } else {
        # Std = 06:00-18:00 Lun-Ven (M-F)
        $Cmd = "net user $SamName /times:M-F,06:00-18:00 /domain"
        $Type = "Std (6-18h)"
    }

    # Execution silencieuse
    Invoke-Expression $Cmd | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: $SamName -> $Type" -ForegroundColor Green
        if ($IsIT) { $ITApplied++ } else { $StdApplied++ }
    } else {
        Write-Host "ERREUR: $SamName (Code $LASTEXITCODE)" -ForegroundColor Red
        $Failed++
    }
}

# --- [5] Bilan ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BILAN IMPORT & CONFIGURATION" -ForegroundColor Green
Write-Host "Utilisateurs traites: $UserCount" -ForegroundColor Green
Write-Host "Horaires configures:" -ForegroundColor Green
Write-Host "  - Standard (M-F 6-18h): $StdApplied" -ForegroundColor Green
Write-Host "  - IT (24h/24): $ITApplied" -ForegroundColor Green
Write-Host "  - Echecs: $Failed" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Green
