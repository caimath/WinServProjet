# ════════════════════════════════════════════════════════════════════════════
# SCRIPT COMPLET : STRUCTURE + GROUPES + AGDLP + PERMISSIONS (v4 - FINAL)
# Respecte les consignes tout en maintenant AGDLP
# FIX: Structure corrigée avec les vrais SamAccountName du CSV (Prenom.Nom)
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"
$CSVPath = "C:\users\Administrator\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "AGDLP COMPLET - Structure + Groupes + Permissions (v4 - FINAL)" -ForegroundColor Cyan
Write-Host "Domain: $Domain" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

# --- [1] CREER LES DOSSIERS ---
Write-Host "`n[1/7] Creation de la structure de dossiers..." -ForegroundColor Yellow

# STRUCTURE CORRIGEE : Format Prenom.Nom
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
        "HotLine"       = "rayan.aimant"
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

# Creer racine
if (-not (Test-Path $RootPath)) {
    New-Item -ItemType Directory -Path $RootPath -Force | Out-Null
    Write-Host "Dossier racine cree: $RootPath"
}

# Creer Commun
$CommonPath = Join-Path $RootPath "Commun"
if (-not (Test-Path $CommonPath)) {
    New-Item -ItemType Directory -Path $CommonPath -Force | Out-Null
    Write-Host "Dossier cree: Commun"
}

# Creer categories et sous-depts
foreach ($Category in $Structure.Keys) {
    $CategoryPath = Join-Path $RootPath $Category
    
    if (-not (Test-Path $CategoryPath)) {
        New-Item -ItemType Directory -Path $CategoryPath -Force | Out-Null
        Write-Host "Dossier cree: $Category"
    }
    
    foreach ($SubDept in $Structure[$Category].Keys) {
        $SubPath = Join-Path $CategoryPath $SubDept
        
        if (-not (Test-Path $SubPath)) {
            New-Item -ItemType Directory -Path $SubPath -Force | Out-Null
            Write-Host "Dossier cree: $Category\$SubDept"
        }
    }
}

Write-Host "Dossiers crees: OK"

# --- [2] CHARGER LES UTILISATEURS ---
Write-Host "`n[2/7] Chargement des utilisateurs..." -ForegroundColor Yellow
$Users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8
Write-Host "Utilisateurs charges: $($Users.Count)"

# --- [CORRECTION] VALIDER LES RESPONSABLES DANS AD ---
Write-Host "`n[2.5/7] Validation des responsables dans AD..." -ForegroundColor Yellow

$ValidManagers = @{}
foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $ManagerFromStructure = $Structure[$Category][$SubDept]
        
        # Chercher le user dans AD
        $AdUser = $null
        try {
            $AdUser = Get-ADUser -Filter "SamAccountName -eq '$ManagerFromStructure'" -ErrorAction SilentlyContinue
        } catch { }
        
        if ($AdUser) {
            $ValidManagers["$Category|$SubDept"] = $AdUser.SamAccountName
            Write-Host "OK Responsable valide: $Category > $SubDept = $($AdUser.SamAccountName)" -ForegroundColor Green
        } else {
            Write-Host "MISSING Responsable: $Category > $SubDept = $ManagerFromStructure" -ForegroundColor Red
            $ValidManagers["$Category|$SubDept"] = $null
        }
    }
}

# --- [3] CREER LES GROUPES GLOBAUX (A > G) ---
Write-Host "`n[3/7] Creation des groupes globaux (A > G)..." -ForegroundColor Yellow

foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $GlobalGroupName = "GG_$SubDept"
        
        $ExistingGroup = Get-ADGroup -Filter "SamAccountName -eq '$GlobalGroupName'" -ErrorAction SilentlyContinue
        
        if (-not $ExistingGroup) {
            try {
                New-ADGroup -SamAccountName $GlobalGroupName -Name $GlobalGroupName `
                    -GroupScope Global -GroupCategory Security `
                    -DisplayName "Global - $SubDept" `
                    -Description "Groupe global: Utilisateurs de $SubDept" `
                    -Path $DomainDN -Confirm:$false
                Write-Host "Groupe global cree: $GlobalGroupName"
            } catch {
                Write-Host "ERREUR creation GG: $GlobalGroupName - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Direction
$ExistingDir = Get-ADGroup -Filter "SamAccountName -eq 'GG_Direction'" -ErrorAction SilentlyContinue
if (-not $ExistingDir) {
    try {
        New-ADGroup -SamAccountName "GG_Direction" -Name "GG_Direction" `
            -GroupScope Global -GroupCategory Security `
            -DisplayName "Global - Direction" `
            -Description "Groupe global: Direction" `
            -Path $DomainDN -Confirm:$false
        Write-Host "Groupe global cree: GG_Direction"
    } catch {
        Write-Host "ERREUR creation GG_Direction - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- [4] CREER LES GROUPES LOCAUX (G > L) ---
Write-Host "`n[4/7] Creation des groupes locaux de domaine (G > L)..." -ForegroundColor Yellow

foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        # Groupe pour les users du sous-dept (RW)
        $DLGroupRW = "DL_${Category}_${SubDept}_RW"
        $ExistingRW = Get-ADGroup -Filter "SamAccountName -eq '$DLGroupRW'" -ErrorAction SilentlyContinue
        if (-not $ExistingRW) {
            try {
                New-ADGroup -SamAccountName $DLGroupRW -Name $DLGroupRW `
                    -GroupScope DomainLocal -GroupCategory Security `
                    -DisplayName "DL - $Category - $SubDept - RW" `
                    -Description "Groupe local: R/W sur $SubDept" `
                    -Path $DomainDN -Confirm:$false
                Write-Host "Groupe local cree: $DLGroupRW"
            } catch {
                Write-Host "ERREUR creation DL RW: $DLGroupRW - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # Groupe pour les autres (Read)
        $DLGroupR = "DL_${Category}_${SubDept}_R"
        $ExistingR = Get-ADGroup -Filter "SamAccountName -eq '$DLGroupR'" -ErrorAction SilentlyContinue
        if (-not $ExistingR) {
            try {
                New-ADGroup -SamAccountName $DLGroupR -Name $DLGroupR `
                    -GroupScope DomainLocal -GroupCategory Security `
                    -DisplayName "DL - $Category - $SubDept - Read" `
                    -Description "Groupe local: Lecture sur $SubDept" `
                    -Path $DomainDN -Confirm:$false
                Write-Host "Groupe local cree: $DLGroupR"
            } catch {
                Write-Host "ERREUR creation DL R: $DLGroupR - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    # Groupe pour la categorie (tous lisent)
    $DLCategoryR = "DL_${Category}_R"
    $ExistingCat = Get-ADGroup -Filter "SamAccountName -eq '$DLCategoryR'" -ErrorAction SilentlyContinue
    if (-not $ExistingCat) {
        try {
            New-ADGroup -SamAccountName $DLCategoryR -Name $DLCategoryR `
                -GroupScope DomainLocal -GroupCategory Security `
                -DisplayName "DL - $Category - Read" `
                -Description "Groupe local: Lecture sur $Category" `
                -Path $DomainDN -Confirm:$false
            Write-Host "Groupe local cree: $DLCategoryR"
        } catch {
            Write-Host "ERREUR creation DL Category: $DLCategoryR - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Groupes Commun
$ExistingCommunR = Get-ADGroup -Filter "SamAccountName -eq 'DL_Commun_R'" -ErrorAction SilentlyContinue
if (-not $ExistingCommunR) {
    try {
        New-ADGroup -SamAccountName "DL_Commun_R" -Name "DL_Commun_R" `
            -GroupScope DomainLocal -GroupCategory Security `
            -DisplayName "DL - Commun - Read" `
            -Description "Groupe local: Lecture Commun" `
            -Path $DomainDN -Confirm:$false
        Write-Host "Groupe local cree: DL_Commun_R"
    } catch {
        Write-Host "ERREUR creation DL_Commun_R - $($_.Exception.Message)" -ForegroundColor Red
    }
}

$ExistingCommunRW = Get-ADGroup -Filter "SamAccountName -eq 'DL_Commun_RW'" -ErrorAction SilentlyContinue
if (-not $ExistingCommunRW) {
    try {
        New-ADGroup -SamAccountName "DL_Commun_RW" -Name "DL_Commun_RW" `
            -GroupScope DomainLocal -GroupCategory Security `
            -DisplayName "DL - Commun - RW" `
            -Description "Groupe local: R/W Commun (responsables)" `
            -Path $DomainDN -Confirm:$false
        Write-Host "Groupe local cree: DL_Commun_RW"
    } catch {
        Write-Host "ERREUR creation DL_Commun_RW - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Groupe Direction Full
$ExistingDirFull = Get-ADGroup -Filter "SamAccountName -eq 'DL_Direction_Full'" -ErrorAction SilentlyContinue
if (-not $ExistingDirFull) {
    try {
        New-ADGroup -SamAccountName "DL_Direction_Full" -Name "DL_Direction_Full" `
            -GroupScope DomainLocal -GroupCategory Security `
            -DisplayName "DL - Direction - Full" `
            -Description "Groupe local: Full access Direction" `
            -Path $DomainDN -Confirm:$false
        Write-Host "Groupe local cree: DL_Direction_Full"
    } catch {
        Write-Host "ERREUR creation DL_Direction_Full - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- [5] AJOUTER UTILISATEURS AUX GROUPES GLOBAUX (A > G) ---
Write-Host "`n[5/7] Ajout des utilisateurs aux groupes globaux (A > G)..." -ForegroundColor Yellow

$AllUsers = Get-ADUser -Filter "Enabled -eq 'True'" -SearchBase $DomainDN | Where-Object { $_.SamAccountName -notmatch "^krbtgt|Administrator|Guest" }
$ProcessedCount = 0

foreach ($User in $AllUsers) {
    $SamName = $User.SamAccountName
    $OU = $User.DistinguishedName
    
    # Extraire sous-dept et categorie de l'OU
    $OUParts = $OU -split "," | Where-Object { $_ -like "OU=*" }
    
    if ($OUParts.Count -ge 2) {
        $SubDept = ($OUParts[0] -replace "OU=", "").Trim()
        $Category = ($OUParts[1] -replace "OU=", "").Trim()
        
        $GlobalGroupName = "GG_$SubDept"
        
        try {
            $GlobalGroup = Get-ADGroup -Filter "SamAccountName -eq '$GlobalGroupName'" -ErrorAction SilentlyContinue
            
            if ($GlobalGroup) {
                $IsMember = Get-ADGroupMember -Identity $GlobalGroupName -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $SamName }
                
                if (-not $IsMember) {
                    Add-ADGroupMember -Identity $GlobalGroupName -Members $SamName -Confirm:$false -ErrorAction SilentlyContinue
                    $ProcessedCount++
                }
            }
        } catch { }
    } elseif ($OUParts.Count -eq 1) {
        # OU simple (Direction, Recherche, etc.)
        $SubDept = ($OUParts[0] -replace "OU=", "").Trim()
        $GlobalGroupName = "GG_$SubDept"
        
        try {
            $GlobalGroup = Get-ADGroup -Filter "SamAccountName -eq '$GlobalGroupName'" -ErrorAction SilentlyContinue
            
            if ($GlobalGroup) {
                $IsMember = Get-ADGroupMember -Identity $GlobalGroupName -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $SamName }
                
                if (-not $IsMember) {
                    Add-ADGroupMember -Identity $GlobalGroupName -Members $SamName -Confirm:$false -ErrorAction SilentlyContinue
                    $ProcessedCount++
                }
            }
        } catch { }
    }
}

# Direction
$DirectionUsers = $AllUsers | Where-Object { $_.DistinguishedName -like "*OU=Direction*" }
foreach ($User in $DirectionUsers) {
    try {
        $IsMember = Get-ADGroupMember -Identity "GG_Direction" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $User.SamAccountName }
        if (-not $IsMember) {
            Add-ADGroupMember -Identity "GG_Direction" -Members $User.SamAccountName -Confirm:$false -ErrorAction SilentlyContinue
            $ProcessedCount++
        }
    } catch { }
}

Write-Host "Utilisateurs ajoutes aux groupes globaux: $ProcessedCount"

# --- [6] AJOUTER GROUPES GLOBAUX AUX GROUPES LOCAUX (G > L) ---
Write-Host "`n[6/7] Ajout des groupes globaux aux groupes locaux (G > L)..." -ForegroundColor Yellow

foreach ($Category in $Structure.Keys) {
    $SubDepts = $Structure[$Category].Keys
    
    foreach ($SubDept in $SubDepts) {
        $GlobalGroupName = "GG_$SubDept"
        $DLGroupRW = "DL_${Category}_${SubDept}_RW"
        $DLGroupR = "DL_${Category}_${SubDept}_R"
        $DLCategoryR = "DL_${Category}_R"
        
        # Ajouter au groupe RW (users du sous-dept modifient)
        try {
            $IsMemberRW = Get-ADGroupMember -Identity $DLGroupRW -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $GlobalGroupName }
            if (-not $IsMemberRW) {
                Add-ADGroupMember -Identity $DLGroupRW -Members $GlobalGroupName -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "$GlobalGroupName -> $DLGroupRW"
            }
        } catch { }
        
        # Ajouter les autres sous-depts au groupe Read
        foreach ($OtherSubDept in $SubDepts) {
            if ($OtherSubDept -ne $SubDept) {
                $OtherGlobalGroupName = "GG_$OtherSubDept"
                try {
                    $IsMemberR = Get-ADGroupMember -Identity $DLGroupR -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $OtherGlobalGroupName }
                    if (-not $IsMemberR) {
                        Add-ADGroupMember -Identity $DLGroupR -Members $OtherGlobalGroupName -Confirm:$false -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
        }
        
        # Ajouter au groupe Category Read (tous lisent la categorie)
        try {
            $IsMemberCat = Get-ADGroupMember -Identity $DLCategoryR -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $GlobalGroupName }
            if (-not $IsMemberCat) {
                Add-ADGroupMember -Identity $DLCategoryR -Members $GlobalGroupName -Confirm:$false -ErrorAction SilentlyContinue
            }
        } catch { }
    }
}

# Ajouter Direction au groupe Direction Full
try {
    $IsMemberDir = Get-ADGroupMember -Identity "DL_Direction_Full" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq "GG_Direction" }
    if (-not $IsMemberDir) {
        Add-ADGroupMember -Identity "DL_Direction_Full" -Members "GG_Direction" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "GG_Direction -> DL_Direction_Full"
    }
} catch { }

# Ajouter responsables valides à DL_Commun_RW
Write-Host "`nAjout des responsables a DL_Commun_RW..."
foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $ManagerKey = "$Category|$SubDept"
        $Manager = $ValidManagers[$ManagerKey]
        
        if ($Manager) {
            try {
                $IsMemberCommun = Get-ADGroupMember -Identity "DL_Commun_RW" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $Manager }
                if (-not $IsMemberCommun) {
                    Add-ADGroupMember -Identity "DL_Commun_RW" -Members $Manager -Confirm:$false -ErrorAction SilentlyContinue
                    Write-Host "OK $Manager -> DL_Commun_RW" -ForegroundColor Green
                }
            } catch {
                Write-Host "ERREUR ajout $Manager : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host "Groupes globaux ajoutes aux groupes locaux: OK"

# --- [7] APPLIQUER LES PERMISSIONS NTFS (L > Permissions) ---
Write-Host "`n[7/7] Application des permissions NTFS (L > Permissions)..." -ForegroundColor Yellow

function Grant-FolderPermission {
    param(
        [string]$Path,
        [string]$GroupName,
        [System.Security.AccessControl.FileSystemRights]$Rights
    )
    
    try {
        $Acl = Get-Acl -Path $Path
        $ExistingRule = $Acl.Access | Where-Object { $_.IdentityReference -like "*$GroupName" -and $_.IsInherited -eq $false }
        
        if (-not $ExistingRule) {
            $Ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$Domain\$GroupName",
                $Rights,
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $Acl.AddAccessRule($Ace)
            Set-Acl -Path $Path -AclObject $Acl
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

# Appliquer sur categories et sous-depts
foreach ($Category in $Structure.Keys) {
    $CategoryPath = Join-Path $RootPath $Category
    $DLCategoryR = "DL_${Category}_R"
    
    # Permission categorie: tous lisent (via groupe category)
    Grant-FolderPermission -Path $CategoryPath -GroupName $DLCategoryR -Rights "Read" | Out-Null
    
    # Permission categorie: responsables du sous-dept en R/W
    foreach ($SubDept in $Structure[$Category].Keys) {
        $ManagerKey = "$Category|$SubDept"
        $Manager = $ValidManagers[$ManagerKey]
        
        if ($Manager) {
            Grant-FolderPermission -Path $CategoryPath -GroupName $Manager -Rights "Modify" | Out-Null
        }
    }
    
    # Permission categorie: Direction modifie
    Grant-FolderPermission -Path $CategoryPath -GroupName "DL_Direction_Full" -Rights "Modify" | Out-Null
    
    Write-Host "Permissions appliquees: $Category"
    
    foreach ($SubDept in $Structure[$Category].Keys) {
        $SubPath = Join-Path $CategoryPath $SubDept
        $DLGroupRW = "DL_${Category}_${SubDept}_RW"
        $DLGroupR = "DL_${Category}_${SubDept}_R"
        
        # Users du sous-dept: Modify
        Grant-FolderPermission -Path $SubPath -GroupName $DLGroupRW -Rights "Modify" | Out-Null
        # Autres sous-depts: Read
        Grant-FolderPermission -Path $SubPath -GroupName $DLGroupR -Rights "Read" | Out-Null
        # Direction: Full
        Grant-FolderPermission -Path $SubPath -GroupName "DL_Direction_Full" -Rights "Modify" | Out-Null
        
        Write-Host "Permissions appliquees: $Category\$SubDept"
    }
}

# Permissions Commun
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Commun_R" -Rights "Read" | Out-Null
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Commun_RW" -Rights "Modify" | Out-Null
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Direction_Full" -Rights "Modify" | Out-Null
Write-Host "Permissions appliquees: Commun"

# --- NOUVEAU : DOSSIER DIRECTION (CONFIDENTIEL) ---
Write-Host "`n[7.5/7] Creation dossier Direction (CONFIDENTIEL)..." -ForegroundColor Yellow

$DirConfPath = Join-Path $RootPath "Direction"
if (-not (Test-Path $DirConfPath)) {
    New-Item -ItemType Directory -Path $DirConfPath -Force | Out-Null
    Write-Host "Dossier cree: Direction"
}

try {
    # Casser l'héritage pour Direction (seulement Direction + Admins)
    $Acl = Get-Acl -Path $DirConfPath
    $Acl.SetAccessRuleProtection($true, $false)
    Set-Acl -Path $DirConfPath -AclObject $Acl
    
    # SYSTEM (par SID)
    $SysAce = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "S-1-5-18",  # SID de SYSTEM
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $Acl = Get-Acl -Path $DirConfPath
    $Acl.AddAccessRule($SysAce)
    Set-Acl -Path $DirConfPath -AclObject $Acl
    
    # Administrators (par SID)
    $AdminAce = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "S-1-5-32-544",  # SID d'Administrators
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $Acl = Get-Acl -Path $DirConfPath
    $Acl.AddAccessRule($AdminAce)
    Set-Acl -Path $DirConfPath -AclObject $Acl
    
    # Direction: FullControl
    Grant-FolderPermission -Path $DirConfPath -GroupName "DL_Direction_Full" -Rights "FullControl" | Out-Null
    
    Write-Host "Permissions appliquees: Direction (CONFIDENTIEL - Direction Only)" -ForegroundColor Green
} catch {
    Write-Host "ERREUR configuration Direction: $($_.Exception.Message)" -ForegroundColor Red
}

# --- BILAN ---
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "CONFIGURATION TERMINEE" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "`nChaines AGDLP appliquees:" -ForegroundColor Cyan
Write-Host "- A (Account) : Utilisateurs dans leurs OUs" -ForegroundColor Green
Write-Host "- G (Global) : Users dans GG_* (par sous-dept)" -ForegroundColor Green
Write-Host "- L (Local) : GG_* dans DL_* (par categorie)" -ForegroundColor Green
Write-Host "- P (Permission) : DL_* sur dossiers NTFS" -ForegroundColor Green
Write-Host "`nConsignes respectees:" -ForegroundColor Cyan
Write-Host "- Dossier DEPT: Tous en R, Responsables en R/W, Direction en R/W" -ForegroundColor Green
Write-Host "- Dossier SOUS-DEPT: Users en R/W, Autres en R, Direction en R/W" -ForegroundColor Green
Write-Host "- Dossier COMMUN: Tous en R, Responsables en R/W" -ForegroundColor Green
Write-Host "- Dossier DIRECTION: Direction UNIQUEMENT (FullControl)" -ForegroundColor Green
Write-Host "`nStructure finale:" -ForegroundColor Cyan
Write-Host "- Dossiers: Tous crees automatiquement" -ForegroundColor Green
Write-Host "- Groupes: Globaux et Locaux crees" -ForegroundColor Green
Write-Host "- Users: Ajoutes aux groupes (AGDLP)" -ForegroundColor Green
Write-Host "- Permissions: Appliquees via groupes locaux (L > P)" -ForegroundColor Green
Write-Host "- Responsables: Valides depuis AD + format Prenom.Nom + SIDs pour groupes speciaux" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
