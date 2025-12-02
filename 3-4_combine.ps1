# SCRIPT 03-04 FUSIONNE REDUIT : IMPORT UTILISATEURS + CONFIGURATION AD
# Combine : Création OUs + Utilisateurs + Mots de passe aléatoires + Délégation
# PowerShell 5.1 COMPATIBLE

$CSVPath = "$env:USERPROFILE\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "IMPORT UTILISATEURS + CONFIG AD (SANS PSO/GROUPES)" -ForegroundColor Cyan
Write-Host "Domaine: Belgique.lan" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $CSVPath)) {
    Write-Host "ERREUR: Fichier CSV non trouve!" -ForegroundColor Red
    Break
}

# --- [1] Lecture CSV ---
Write-Host "`n[1/6] Lecture du CSV..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8
Write-Host "OK: $($Users.Count) utilisateurs a importer" -ForegroundColor Green

# --- [2] Analyse Structure OUs ---
Write-Host "`n[2/6] Analyse et Creation de la structure OUs..." -ForegroundColor Yellow

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

# 2c. Création OU Ordinateurs
Write-Host "`nCreation OU Ordinateurs..." -ForegroundColor Yellow
$ComputersOUPath = "OU=Ordinateurs,DC=Belgique,DC=lan"
try {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Ordinateurs'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "Ordinateurs" -Path "DC=Belgique,DC=lan" -Confirm:$false
        Write-Host "OK: OU Ordinateurs creee" -ForegroundColor Green
    }
} catch { Write-Host "ERREUR OU Ordinateurs: $_" -ForegroundColor Red }

# --- [3] Fonction generation mots de passe securises ---
Write-Host "`n[3/6] Generation mots de passe aleatoires (20 chars)..." -ForegroundColor Yellow

function Generate-SecurePassword {
    $Length = 20
    $Chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*"
    $SecureRandom = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $RandomBytes = New-Object byte[] $Length
    $SecureRandom.GetBytes($RandomBytes)
    $Password = ""
    foreach ($Byte in $RandomBytes) {
        $Password += $Chars[$Byte % $Chars.Length]
    }
    # Garantir complexité : 1 majuscule + 1 minuscule + 1 chiffre + 1 spécial
    $Password = "A1!@" + $Password.Substring(0, 16)
    return $Password
}

# --- [4] Creation Users avec mots de passe aleatoires ---
Write-Host "`n[4/6] Creation des utilisateurs..." -ForegroundColor Yellow

$UserCount = 0
$ErrorCount = 0
$UsedAccounts = @{}
$PasswordLog = @()

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

    # Détermination du chemin OU
    if ($Departement.Contains("/")) {
        $Parts = $Departement.Split("/")
        $SubDept = $Parts[0].Trim()
        $Category = $Parts[1].Trim()
        $OUPath = "OU=${SubDept},OU=${Category},DC=Belgique,DC=lan"
    } else {
        $OUPath = "OU=${Departement},DC=Belgique,DC=lan"
    }

    # Génération mot de passe ALEATOIRE
    $NewPassword = Generate-SecurePassword
    $SecurePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '${SamName}'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name "$Prenom $Nom" -GivenName $Prenom -Surname $Nom -SamAccountName $SamName `
                -UserPrincipalName "$SamName@Belgique.lan" -DisplayName "$Prenom $Nom" -Title $Fonction `
                -Department $Departement -Office $Bureau -Path $OUPath -AccountPassword $SecurePassword `
                -Enabled $true -ChangePasswordAtLogon $false -Confirm:$false
            
            Write-Host "OK: $SamName ($Departement)" -ForegroundColor Green
            $UserCount++
            
            # Enregistrement du mot de passe
            $PasswordLog += [PSCustomObject]@{
                SamAccountName = $SamName
                Password = $NewPassword
                DateChanged = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            Write-Host "SKIP: $SamName existe deja" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERREUR: $SamName ($Departement) - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

# Export CSV mots de passe
$PasswordLogPath = "$env:USERPROFILE\Downloads\Passwords_Export.csv"
try {
    $PasswordLog | Export-Csv -Path $PasswordLogPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Host "OK: Mots de passe exportes ($($PasswordLog.Count) utilisateurs)" -ForegroundColor Green
    Write-Host "    -> $PasswordLogPath" -ForegroundColor Cyan
} catch {
    Write-Host "ERREUR export CSV: $_" -ForegroundColor Red
}

# --- [5] Configuration delegation administrative + ACL ---
Write-Host "`n[5/6] Configuration delegation administrative..." -ForegroundColor Yellow

$DelegationMap = @{
    "Commerciaux" = "cline.glinka"
    "Technique" = "axel.irakoze"
    "Informatique" = "adrien.ilic"
    "Ressources humaines" = "romain.marcel"
    "Direction" = "pol.kuntondaluezi"
    "R&D" = "louismichel.galand"
    "Marketting" = "maxime.gudin"
    "Finances" = "jrmy.higueraslozano"
}

$DelegCount = 0
foreach ($Dept in $DelegationMap.Keys) {
    $ManagerID = $DelegationMap[$Dept]
    $Manager = Get-ADUser -Identity $ManagerID -Properties DisplayName, Title -ErrorAction SilentlyContinue
    
    if ($Manager) {
        Write-Host "Delegation $Dept ->" -NoNewline
        Write-Host " $($Manager.DisplayName) ($ManagerID)" -ForegroundColor Green
        $DelegCount++
    } else {
        Write-Host "Delegation $Dept ->" -NoNewline
        Write-Host " ERREUR (User introuvable)" -ForegroundColor Red
    }
}

# Application permissions ACL
$DeptOUMap = @{
    "Commerciaux" = "OU=Commerciaux,DC=Belgique,DC=lan"
    "Technique" = "OU=Technique,DC=Belgique,DC=lan"
    "Informatique" = "OU=Informatique,DC=Belgique,DC=lan"
    "Ressources humaines" = "OU=Ressources humaines,DC=Belgique,DC=lan"
    "Direction" = "OU=Direction,DC=Belgique,DC=lan"
    "R&D" = "OU=R&D,DC=Belgique,DC=lan"
    "Marketting" = "OU=Marketting,DC=Belgique,DC=lan"
    "Finances" = "OU=Finances,DC=Belgique,DC=lan"
}

$PermCount = 0
$PermFail = 0

foreach ($Dept in $DelegationMap.Keys) {
    $ManagerID = $DelegationMap[$Dept]
    $OUPath = $DeptOUMap[$Dept]
    
    $User = Get-ADUser -Filter "SamAccountName -eq '${ManagerID}'" -Properties SID -ErrorAction SilentlyContinue
    if (-not $User) {
        Write-Host "ERREUR: User $ManagerID non trouve" -ForegroundColor Red
        $PermFail++
        continue
    }
    
    $OU = Get-ADOrganizationalUnit -Filter "distinguishedName -eq '${OUPath}'" -ErrorAction SilentlyContinue
    if (-not $OU) {
        Write-Host "ERREUR: OU $OUPath non trouvee pour $Dept" -ForegroundColor Red
        $PermFail++
        continue
    }
    
    try {
        $ACL = Get-Acl -Path "AD:\$($OU.DistinguishedName)"
        $UserSID = $User.SID
        
        # Permission 1: Reset Password
        $ResetPasswordGUID = [GUID]"00299570-246d-11d0-a768-00aa006e0529"
        $ACE_Reset = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $UserSID,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $ResetPasswordGUID,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )
        
        # Permission 2: Modify All Properties
        $ACE_Write = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $UserSID,
            [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
            [System.Security.AccessControl.AccessControlType]::Allow,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )
        
        $ACL.AddAccessRule($ACE_Reset)
        $ACL.AddAccessRule($ACE_Write)
        
        Set-Acl -Path "AD:\$($OU.DistinguishedName)" -AclObject $ACL
        
        Write-Host "✓ ACL APPLIQUEE: ${ManagerID} -> ${Dept}" -ForegroundColor Green
        $PermCount++
        
    } catch {
        Write-Host "✗ ERREUR ACL ${ManagerID}: $_" -ForegroundColor Red
        $PermFail++
    }
}

# --- [6] Verification finale ---
Write-Host "`n[6/6] Verification finale..." -ForegroundColor Yellow

Write-Host "Utilisateurs avec DisplayName vide:" -ForegroundColor Yellow
$EmptyDisplayNames = Get-ADUser -Filter * -SearchBase "DC=Belgique,DC=lan" -Properties DisplayName | `
    Where-Object { [string]::IsNullOrWhiteSpace($_.DisplayName) } | `
    Measure-Object
Write-Host "  Trouvs: $($EmptyDisplayNames.Count)" -ForegroundColor Green

# --- BILAN FINAL ---
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "CONFIGURATION COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Utilisateurs:" -ForegroundColor Green
Write-Host "  - Crées: $UserCount" -ForegroundColor Green
Write-Host "  - Erreurs: $ErrorCount" -ForegroundColor $(if($ErrorCount -gt 0){"Yellow"}else{"Green"})
Write-Host "Délégations:" -ForegroundColor Green
Write-Host "  - Configurées: $DelegCount" -ForegroundColor Green
Write-Host "  - Permissions ACL appliquées: $PermCount" -ForegroundColor $(if($PermCount -eq 8){"Green"}else{"Yellow"})
Write-Host "`n⚠️  IMPORTANT:" -ForegroundColor Yellow
Write-Host "  - Mots de passe: $PasswordLogPath" -ForegroundColor Yellow
Write-Host "  - À distribuer par mail chiffré uniquement" -ForegroundColor Red
Write-Host "  - À SUPPRIMER après distribution" -ForegroundColor Red
Write-Host "  - Les groupes et PSO doivent être créés séparément" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
