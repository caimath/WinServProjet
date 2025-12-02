# ════════════════════════════════════════════════════════════════════════════
# SCRIPT COMPLET : STRUCTURE + GROUPES + AGDLP + PERMISSIONS
# Fichier: 05-AGDLP-Complet.ps1
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"
$CSVPath = "C:\users\Administrator\Downloads\Employes-Liste6_ADAPTEE.csv"

Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "AGDLP COMPLET - Structure + Groupes + Permissions" -ForegroundColor Cyan
Write-Host "Domain: $Domain" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

# --- [1] CREER LES DOSSIERS ---
Write-Host "`n[1/7] Creation de la structure de dossiers..." -ForegroundColor Yellow

$Structure = @{
    "Ressources humaines" = @{
        "Gestion du personnel" = "assiene.alban"
        "Recrutement"          = "bellante.francois"
    }
    "Finances" = @{
        "Comptabilité"    = "craeyegeoffrey"
        "Investissements" = "paris.jason"
    }
    "Informatique" = @{
        "Développement" = "bavoua.kenfack"
        "HotLine"       = "aimant.rayan"
        "Systèmes"      = "baisagurova.arnaud"
    }
    "R&D" = @{
        "Recherche" = "alkhamry.lorraine"
        "Testing"   = "bayanaknlend.emilie"
    }
    "Technique" = @{
        "Achat"       = "alaca.ruben"
        "Techniciens" = "chiarelli.geoffrey"
    }
    "Commerciaux" = @{
        "Sédentaires" = "balci.dorcas"
        "Technico"    = "cambier.adriano"
    }
    "Marketing" = @{
        "Site1" = "brodkom.remi"
        "Site2" = "amand.simon"
        "Site3" = "aubly.vincent"
        "Site4" = "brogniez.audrey"
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

# --- [3] CREER LES GROUPES GLOBAUX ---
Write-Host "`n[3/7] Creation des groupes globaux..." -ForegroundColor Yellow

foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        $GlobalGroupName = "GG_$SubDept"
        
        $ExistingGroup = Get-ADGroup -Filter "SamAccountName -eq '$GlobalGroupName'" -ErrorAction SilentlyContinue
        
        if (-not $ExistingGroup) {
            New-ADGroup -SamAccountName $GlobalGroupName -Name $GlobalGroupName `
                -GroupScope Global -GroupCategory Security `
                -DisplayName "Global - $SubDept" `
                -Description "Groupe global: Utilisateurs de $SubDept" `
                -Path $DomainDN -Confirm:$false
            Write-Host "Groupe global cree: $GlobalGroupName"
        }
    }
}

# Direction
$ExistingDir = Get-ADGroup -Filter "SamAccountName -eq 'GG_Direction'" -ErrorAction SilentlyContinue
if (-not $ExistingDir) {
    New-ADGroup -SamAccountName "GG_Direction" -Name "GG_Direction" `
        -GroupScope Global -GroupCategory Security `
        -DisplayName "Global - Direction" `
        -Description "Groupe global: Direction" `
        -Path $DomainDN -Confirm:$false
    Write-Host "Groupe global cree: GG_Direction"
}

# --- [4] CREER LES GROUPES LOCAUX ---
Write-Host "`n[4/7] Creation des groupes locaux de domaine..." -ForegroundColor Yellow

foreach ($Category in $Structure.Keys) {
    foreach ($SubDept in $Structure[$Category].Keys) {
        # Groupe pour les users du sous-dept (RW)
        $DLGroupRW = "DL_${Category}_${SubDept}_RW"
        $ExistingRW = Get-ADGroup -Filter "SamAccountName -eq '$DLGroupRW'" -ErrorAction SilentlyContinue
        if (-not $ExistingRW) {
            New-ADGroup -SamAccountName $DLGroupRW -Name $DLGroupRW `
                -GroupScope DomainLocal -GroupCategory Security `
                -DisplayName "DL - $Category - $SubDept - RW" `
                -Description "Groupe local: R/W sur $SubDept" `
                -Path $DomainDN -Confirm:$false
            Write-Host "Groupe local cree: $DLGroupRW"
        }
        
        # Groupe pour les autres (Read)
        $DLGroupR = "DL_${Category}_${SubDept}_R"
        $ExistingR = Get-ADGroup -Filter "SamAccountName -eq '$DLGroupR'" -ErrorAction SilentlyContinue
        if (-not $ExistingR) {
            New-ADGroup -SamAccountName $DLGroupR -Name $DLGroupR `
                -GroupScope DomainLocal -GroupCategory Security `
                -DisplayName "DL - $Category - $SubDept - Read" `
                -Description "Groupe local: Lecture sur $SubDept" `
                -Path $DomainDN -Confirm:$false
            Write-Host "Groupe local cree: $DLGroupR"
        }
    }
    
    # Groupe pour la categorie (tous lisent)
    $DLCategoryR = "DL_${Category}_R"
    $ExistingCat = Get-ADGroup -Filter "SamAccountName -eq '$DLCategoryR'" -ErrorAction SilentlyContinue
    if (-not $ExistingCat) {
        New-ADGroup -SamAccountName $DLCategoryR -Name $DLCategoryR `
            -GroupScope DomainLocal -GroupCategory Security `
            -DisplayName "DL - $Category - Read" `
            -Description "Groupe local: Lecture sur $Category" `
            -Path $DomainDN -Confirm:$false
        Write-Host "Groupe local cree: $DLCategoryR"
    }
}

# Groupes Commun
$ExistingCommunR = Get-ADGroup -Filter "SamAccountName -eq 'DL_Commun_R'" -ErrorAction SilentlyContinue
if (-not $ExistingCommunR) {
    New-ADGroup -SamAccountName "DL_Commun_R" -Name "DL_Commun_R" `
        -GroupScope DomainLocal -GroupCategory Security `
        -DisplayName "DL - Commun - Read" `
        -Description "Groupe local: Lecture Commun" `
        -Path $DomainDN -Confirm:$false
    Write-Host "Groupe local cree: DL_Commun_R"
}

$ExistingCommunRW = Get-ADGroup -Filter "SamAccountName -eq 'DL_Commun_RW'" -ErrorAction SilentlyContinue
if (-not $ExistingCommunRW) {
    New-ADGroup -SamAccountName "DL_Commun_RW" -Name "DL_Commun_RW" `
        -GroupScope DomainLocal -GroupCategory Security `
        -DisplayName "DL - Commun - RW" `
        -Description "Groupe local: R/W Commun (responsables)" `
        -Path $DomainDN -Confirm:$false
    Write-Host "Groupe local cree: DL_Commun_RW"
}

# Groupe Direction Full
$ExistingDirFull = Get-ADGroup -Filter "SamAccountName -eq 'DL_Direction_Full'" -ErrorAction SilentlyContinue
if (-not $ExistingDirFull) {
    New-ADGroup -SamAccountName "DL_Direction_Full" -Name "DL_Direction_Full" `
        -GroupScope DomainLocal -GroupCategory Security `
        -DisplayName "DL - Direction - Full" `
        -Description "Groupe local: Full access Direction" `
        -Path $DomainDN -Confirm:$false
    Write-Host "Groupe local cree: DL_Direction_Full"
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
        
        $GlobalGroup = Get-ADGroup -Filter "SamAccountName -eq '$GlobalGroupName'" -ErrorAction SilentlyContinue
        
        if ($GlobalGroup) {
            $IsMember = Get-ADGroupMember -Identity $GlobalGroupName -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $SamName }
            
            if (-not $IsMember) {
                Add-ADGroupMember -Identity $GlobalGroupName -Members $SamName -Confirm:$false
                $ProcessedCount++
            }
        }
    }
}

# Direction
$DirectionUsers = $AllUsers | Where-Object { $_.DistinguishedName -like "*OU=Direction*" }
foreach ($User in $DirectionUsers) {
    $IsMember = Get-ADGroupMember -Identity "GG_Direction" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $User.SamAccountName }
    if (-not $IsMember) {
        Add-ADGroupMember -Identity "GG_Direction" -Members $User.SamAccountName -Confirm:$false
        $ProcessedCount++
    }
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
        $IsMemberRW = Get-ADGroupMember -Identity $DLGroupRW -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $GlobalGroupName }
        if (-not $IsMemberRW) {
            Add-ADGroupMember -Identity $DLGroupRW -Members $GlobalGroupName -Confirm:$false
            Write-Host "$GlobalGroupName -> $DLGroupRW"
        }
        
        # Ajouter les autres sous-depts au groupe Read
        foreach ($OtherSubDept in $SubDepts) {
            if ($OtherSubDept -ne $SubDept) {
                $OtherGlobalGroupName = "GG_$OtherSubDept"
                $IsMemberR = Get-ADGroupMember -Identity $DLGroupR -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $OtherGlobalGroupName }
                if (-not $IsMemberR) {
                    Add-ADGroupMember -Identity $DLGroupR -Members $OtherGlobalGroupName -Confirm:$false
                }
            }
        }
        
        # Ajouter au groupe Category Read (tous lisent la categorie)
        $IsMemberCat = Get-ADGroupMember -Identity $DLCategoryR -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $GlobalGroupName }
        if (-not $IsMemberCat) {
            Add-ADGroupMember -Identity $DLCategoryR -Members $GlobalGroupName -Confirm:$false
        }
    }
}

# Ajouter Direction au groupe Direction Full
$IsMemberDir = Get-ADGroupMember -Identity "DL_Direction_Full" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq "GG_Direction" }
if (-not $IsMemberDir) {
    Add-ADGroupMember -Identity "DL_Direction_Full" -Members "GG_Direction" -Confirm:$false
    Write-Host "GG_Direction -> DL_Direction_Full"
}

Write-Host "Groupes globaux ajoutes aux groupes locaux: OK"

# --- [7] APPLIQUER LES PERMISSIONS NTFS (L > Permissions) ---
Write-Host "`n[7/7] Application des permissions NTFS..." -ForegroundColor Yellow

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
    
    # Permission categorie: tous lisent
    Grant-FolderPermission -Path $CategoryPath -GroupName $DLCategoryR -Rights "Read"
    # Permission categorie: Direction modifie
    Grant-FolderPermission -Path $CategoryPath -GroupName "DL_Direction_Full" -Rights "Modify"
    
    Write-Host "Permissions appliquees: $Category"
    
    foreach ($SubDept in $Structure[$Category].Keys) {
        $SubPath = Join-Path $CategoryPath $SubDept
        $DLGroupRW = "DL_${Category}_${SubDept}_RW"
        $DLGroupR = "DL_${Category}_${SubDept}_R"
        
        # Users du sous-dept: Modify
        Grant-FolderPermission -Path $SubPath -GroupName $DLGroupRW -Rights "Modify"
        # Autres sous-depts: Read
        Grant-FolderPermission -Path $SubPath -GroupName $DLGroupR -Rights "Read"
        # Direction: Full
        Grant-FolderPermission -Path $SubPath -GroupName "DL_Direction_Full" -Rights "Modify"
        
        Write-Host "Permissions appliquees: $Category\$SubDept"
    }
}

# Permissions Commun
$CommonPath = Join-Path $RootPath "Commun"
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Commun_R" -Rights "Read"
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Commun_RW" -Rights "Modify"
Grant-FolderPermission -Path $CommonPath -GroupName "DL_Direction_Full" -Rights "Modify"
Write-Host "Permissions appliquees: Commun"

# --- BILAN ---
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "CONFIGURATION TERMINEE" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "`nChaines AGDLP appliquees:" -ForegroundColor Cyan
Write-Host "- A (Account) : Utilisateurs dans leurs OUs" -ForegroundColor Green
Write-Host "- G (Global) : Users dans GG_* (par sous-dept)" -ForegroundColor Green
Write-Host "- L (Local) : GG_* dans DL_* (par categorie)" -ForegroundColor Green
Write-Host "- P (Permission) : DL_* sur dossiers NTFS" -ForegroundColor Green
Write-Host "`nStructure:" -ForegroundColor Cyan
Write-Host "- Dossiers: Tous crees automatiquement" -ForegroundColor Green
Write-Host "- Groupes: Globaux et Locaux crees" -ForegroundColor Green
Write-Host "- Users: Ajoutes aux groupes (AGDLP)" -ForegroundColor Green
Write-Host "- Permissions: Appliquees sur tous les dossiers" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
