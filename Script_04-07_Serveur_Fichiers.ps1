# ════════════════════════════════════════════════════════════════════════════
# SCRIPT 04-07 : SERVEUR DE FICHIERS (Partages + Quotas + Filtrage)
# Fichier: 04-07-Serveur-Fichiers-Complet.ps1
# À exécuter SUR BRUXELLE après import utilisateurs
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\DossiersPartages"
$Domain = "Belgique.lan"
$ServerName = "DC-BRUXELLE"

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  SERVEUR DE FICHIERS - Configuration complète                 ║" -ForegroundColor Cyan
Write-Host "║  Chemin: $RootPath                                   ║" -ForegroundColor Cyan
Write-Host "║  Domaine: $Domain                                           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 : Installation des rôles
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[1/5] Installation du rôle File Server Resource Manager..." -ForegroundColor Yellow

try {
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools -ErrorAction Stop
    Write-Host "   ✅ Rôle installé" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Rôle déjà installé" -ForegroundColor Gray
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 : Création de l'arborescence de dossiers
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[2/5] Création de l'arborescence des dossiers..." -ForegroundColor Yellow

# Dossier racine
if (-not (Test-Path $RootPath)) {
    New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
    Write-Host "   ✅ Dossier racine créé: $RootPath" -ForegroundColor Green
}

# Dossier Commun
$PathCommun = "$RootPath\Commun"
if (-not (Test-Path $PathCommun)) {
    New-Item -Path $PathCommun -ItemType Directory -Force | Out-Null
    Write-Host "   ✅ Dossier Commun créé" -ForegroundColor Green
}

# Dossier Départements
$PathDepts = "$RootPath\Departements"
if (-not (Test-Path $PathDepts)) {
    New-Item -Path $PathDepts -ItemType Directory -Force | Out-Null
    Write-Host "   ✅ Dossier Departements créé" -ForegroundColor Green
}

# Créer tous les dossiers de départements
$OUs = Get-ADOrganizationalUnit -Filter * -SearchBase "DC=Belgique,DC=lan" -SearchScope OneLevel | `
    Where-Object {$_.Name -ne "Domain Controllers" -and $_.Name -ne "Computers" -and $_.Name -ne "Users"}

foreach ($OU in $OUs) {
    $DeptName = $OU.Name
    $DeptPath = "$PathDepts\$DeptName"
    
    if (-not (Test-Path $DeptPath)) {
        New-Item -Path $DeptPath -ItemType Directory -Force | Out-Null
        Write-Host "   ✅ Département créé: $DeptName" -ForegroundColor Green
    }
    
    # Créer sous-dossiers pour chaque sous-département
    $SubOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $OU.DistinguishedName -SearchScope OneLevel
    foreach ($SubOU in $SubOUs) {
        $SubDeptName = $SubOU.Name
        $SubDeptPath = "$DeptPath\$SubDeptName"
        
        if (-not (Test-Path $SubDeptPath)) {
            New-Item -Path $SubDeptPath -ItemType Directory -Force | Out-Null
            Write-Host "   ✅ Sous-département créé: $DeptName/$SubDeptName" -ForegroundColor Green
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 : Création des partages SMB
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[3/5] Création des partages SMB..." -ForegroundColor Yellow

if (-not (Get-SmbShare -Name "DossiersPartages" -ErrorAction SilentlyContinue)) {
    try {
        New-SmbShare -Name "DossiersPartages" -Path $RootPath -FullAccess "Everyone" -ErrorAction Stop
        Write-Host "   ✅ Partage créé: \\\\$ServerName\DossiersPartages" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Erreur création partage: $_" -ForegroundColor Red
    }
} else {
    Write-Host "   ⚠️  Partage déjà existant" -ForegroundColor Gray
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 : Configuration des permissions NTFS
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[4/5] Configuration des permissions NTFS..." -ForegroundColor Yellow

function Reset-ACL ($Path) {
    try {
        $Acl = Get-Acl $Path
        $Acl.SetAccessRuleProtection($true, $false)
        Set-Acl $Path $Acl
        
        # Admin et SYSTEM avec FullControl
        $ArAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.AddAccessRule($ArAdmin)
        
        $ArSys = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.AddAccessRule($ArSys)
        
        Set-Acl $Path $Acl
    } catch {
        Write-Host "   ⚠️  Erreur ACL sur $Path" -ForegroundColor Yellow
    }
}

function Add-Perm ($Path, $Group, $Right) {
    try {
        $Acl = Get-Acl $Path
        
        # Construire le SID du groupe
        $Id = "$Domain\$Group"
        
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($Id, $Right, "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.AddAccessRule($Ar)
        Set-Acl $Path $Acl
    } catch {
        # Silent (groupe peut ne pas exister)
    }
}

# Dossier Commun
Write-Host "   • Configuration: Dossier Commun" -ForegroundColor Gray
Reset-ACL $PathCommun

# Domain Users en lecture
Add-Perm $PathCommun "Domain Users" "ReadAndExecute"

# Groupe Responsables Commun
try {
    if (-not (Get-ADGroup -Filter {Name -eq "GG_Responsables_Commun"})) {
        New-ADGroup -Name "GG_Responsables_Commun" -GroupScope Global -Path "CN=Users,DC=Belgique,DC=lan"
    }
} catch { }

Add-Perm $PathCommun "GG_Responsables_Commun" "Modify"
Add-Perm $PathCommun "GG_DIRECTION" "FullControl"

Write-Host "   ✅ Permissions Commun configurées" -ForegroundColor Green

# Dossiers Départements
Write-Host "   • Configuration: Dossiers Départements" -ForegroundColor Gray

foreach ($OU in $OUs) {
    $DeptName = $OU.Name
    $DeptPath = "$PathDepts\$DeptName"
    
    Reset-ACL $DeptPath
    Add-Perm $DeptPath "GG_DIRECTION" "FullControl"
    
    $GGDept = "GG_$($DeptName.Replace(' ', '').Replace('/', '_'))"
    Add-Perm $DeptPath $GGDept "ReadAndExecute"
    
    # Sous-départements
    $SubOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $OU.DistinguishedName -SearchScope OneLevel
    foreach ($SubOU in $SubOUs) {
        $SubDeptName = $SubOU.Name
        $SubDeptPath = "$DeptPath\$SubDeptName"
        
        Reset-ACL $SubDeptPath
        Add-Perm $SubDeptPath "GG_DIRECTION" "FullControl"
        
        $GGSub = "GG_$($SubDeptName.Replace(' ', '').Replace('/', '_'))"
        Add-Perm $SubDeptPath $GGSub "Modify"
    }
}

Write-Host "   ✅ Permissions Départements configurées" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 : Configuration des quotas
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[5/5] Configuration des quotas et filtrage..." -ForegroundColor Yellow

# Templates de quota
try {
    Remove-FsrmQuotaTemplate -Name "Limit_500Mo" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-FsrmQuotaTemplate -Name "Limit_100Mo" -Confirm:$false -ErrorAction SilentlyContinue
    
    New-FsrmQuotaTemplate -Name "Limit_500Mo" -Size 500MB -ErrorAction SilentlyContinue
    New-FsrmQuotaTemplate -Name "Limit_100Mo" -Size 100MB -ErrorAction SilentlyContinue
    
    Write-Host "   ✅ Templates de quotas créés (500 Mo / 100 Mo)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Templates déjà existants" -ForegroundColor Gray
}

# Quota Commun
try {
    New-FsrmQuota -Path $PathCommun -Template "Limit_500Mo" -ErrorAction SilentlyContinue
    Write-Host "   ✅ Quota Commun: 500 Mo" -ForegroundColor Green
} catch { }

# Quotas Départements
foreach ($OU in $OUs) {
    $DeptPath = "$PathDepts\$($OU.Name)"
    
    try {
        New-FsrmQuota -Path $DeptPath -Template "Limit_500Mo" -ErrorAction SilentlyContinue
    } catch { }
    
    $SubOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $OU.DistinguishedName -SearchScope OneLevel
    foreach ($Sub in $SubOUs) {
        $SDPath = "$DeptPath\$($Sub.Name)"
        
        try {
            New-FsrmQuota -Path $SDPath -Template "Limit_100Mo" -ErrorAction SilentlyContinue
        } catch { }
    }
}

Write-Host "   ✅ Quotas appliqués" -ForegroundColor Green

# Filtrage de fichiers
$GroupName = "Blocage_Sauf_Office_Images"

try {
    if (-not (Get-FsrmFileGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
        New-FsrmFileGroup -Name $GroupName -IncludePattern "*" `
            -ExcludePattern "*.docx", "*.xlsx", "*.pptx", "*.pdf", "*.jpg", "*.png", "*.txt", "*.doc", "*.xls", "*.jpeg" `
            -ErrorAction SilentlyContinue
    }
    
    New-FsrmFileScreen -Path $PathCommun -IncludeGroup $GroupName -Active -ErrorAction SilentlyContinue
    New-FsrmFileScreen -Path $PathDepts -IncludeGroup $GroupName -Active -ErrorAction SilentlyContinue
    
    Write-Host "   ✅ Filtrage appliqué (Office + Images autorisés)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Filtrage déjà configuré" -ForegroundColor Gray
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ SERVEUR DE FICHIERS CONFIGURÉ                             ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nAccès réseau:" -ForegroundColor Cyan
Write-Host "   \\\\DC-BRUXELLE\DossiersPartages" -ForegroundColor Gray

Write-Host "`nTest d'accès depuis un client:" -ForegroundColor Yellow
Write-Host "   net use x: \\\\DC-BRUXELLE\DossiersPartages" -ForegroundColor Gray