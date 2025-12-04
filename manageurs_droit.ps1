# ════════════════════════════════════════════════════════════════════════════
# SCRIPT: AJOUTER LES MANAGERS DANS LES DL POUR LES PERMISSIONS
# ════════════════════════════════════════════════════════════════════════════

$Domain = "Belgique.lan"
$DomainDN = "DC=Belgique,DC=lan"

Write-Host "════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "AJOUT MANAGERS AUX DL - PERMISSIONS" -ForegroundColor Magenta
Write-Host "════════════════════════════════════════`n" -ForegroundColor Magenta

# Structure: Managers d'un dept peuvent écrire dans tous les sous-depts du département
$Structure = @{
    "Ressources humaines" = @("Gestion du personnel", "Recrutement")
    "Finances" = @("Comptabilité", "Investissements")
    "Informatique" = @("Développement", "HotLine", "Systèmes")
    "R&D" = @("Recherche", "Testing")
    "Technique" = @("Achat", "Techniciens")
    "Commerciaux" = @("Sédentaires", "Technico")
    "Marketting" = @("Site1", "Site2", "Site3", "Site4")
}

# --- [1] AJOUTER GG_Managers_[Dept] DANS LES DL_[SubDept]_RW ---
Write-Host "[1/3] Ajouter managers aux DL_*_RW (Lecture/Ecriture)...`n" -ForegroundColor Yellow

foreach ($MainDept in $Structure.Keys) {
    $ManagerGroupName = "GG_Managers_$MainDept"
    $ManagerGroup = Get-ADGroup -Filter "SamAccountName -eq '$ManagerGroupName'" -ErrorAction SilentlyContinue
    
    if ($ManagerGroup) {
        Write-Host "  📌 $MainDept - Managers peuvent ecrire dans:" -ForegroundColor Cyan
        
        # Pour chaque sous-département du département principal
        foreach ($SubDept in $Structure[$MainDept]) {
            $DLRWName = "DL_$($SubDept)_RW"
            $DLRW = Get-ADGroup -Filter "SamAccountName -eq '$DLRWName'" -ErrorAction SilentlyContinue
            
            if ($DLRW) {
                # Vérifier si le groupe manager est déjà membre
                $IsMember = Get-ADGroupMember -Identity $DLRW -ErrorAction SilentlyContinue | `
                    Where-Object { $_.SamAccountName -eq $ManagerGroupName }
                
                if (-not $IsMember) {
                    try {
                        Add-ADGroupMember -Identity $DLRW -Members $ManagerGroup -Confirm:$false
                        Write-Host "    ✓ $ManagerGroupName -> $DLRWName" -ForegroundColor Green
                    } catch {
                        $ErrorMsg = $_.Exception.Message
                        Write-Host "    ✗ Erreur ajout a $DLRWName : $ErrorMsg" -ForegroundColor Red
                    }
                } else {
                    Write-Host "    ✓ $ManagerGroupName deja dans $DLRWName" -ForegroundColor Gray
                }
            } else {
                Write-Host "    ✗ $DLRWName non trouve" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  ✗ $ManagerGroupName non trouve" -ForegroundColor Red
    }
}

# --- [2] AJOUTER MANAGERS D'UN DEPT AUX DL_RW DES AUTRES SOUS-DEPTS DU MÊME DEPT ---
Write-Host "`n[2/3] Managers peuvent ecrire dans les autres sous-depts du meme dept...`n" -ForegroundColor Yellow

foreach ($MainDept in $Structure.Keys) {
    $ManagerGroupName = "GG_Managers_$MainDept"
    $ManagerGroup = Get-ADGroup -Filter "SamAccountName -eq '$ManagerGroupName'" -ErrorAction SilentlyContinue
    
    if ($ManagerGroup) {
        Write-Host "  📌 $MainDept - Cross-dept access:" -ForegroundColor Cyan
        
        # Pour chaque combinaison de sous-depts différents du même département
        foreach ($SubDept1 in $Structure[$MainDept]) {
            foreach ($SubDept2 in $Structure[$MainDept]) {
                # Éviter d'ajouter deux fois la même chose
                if ($SubDept1 -ne $SubDept2) {
                    $DLRWName = "DL_$($SubDept2)_RW"
                    $DLRW = Get-ADGroup -Filter "SamAccountName -eq '$DLRWName'" -ErrorAction SilentlyContinue
                    
                    if ($DLRW) {
                        $IsMember = Get-ADGroupMember -Identity $DLRW -ErrorAction SilentlyContinue | `
                            Where-Object { $_.SamAccountName -eq $ManagerGroupName }
                        
                        if (-not $IsMember) {
                            try {
                                Add-ADGroupMember -Identity $DLRW -Members $ManagerGroup -Confirm:$false
                                Write-Host "    ✓ $ManagerGroupName -> $DLRWName (cross-access)" -ForegroundColor Green
                            } catch {
                                # Silencieux (déjà ajouté par étape [1])
                            }
                        }
                    }
                }
            }
        }
    }
}

# --- [3] AJOUTER TOUS LES MANAGERS AUX DL_Commun_RW ---
Write-Host "`n[3/3] Ajouter TOUS les managers a DL_Commun_RW...`n" -ForegroundColor Yellow

$DLCommonRW = Get-ADGroup -Filter "SamAccountName -eq 'DL_Commun_RW'" -ErrorAction SilentlyContinue

if ($DLCommonRW) {
    foreach ($MainDept in $Structure.Keys) {
        $ManagerGroupName = "GG_Managers_$MainDept"
        $ManagerGroup = Get-ADGroup -Filter "SamAccountName -eq '$ManagerGroupName'" -ErrorAction SilentlyContinue
        
        if ($ManagerGroup) {
            $IsMember = Get-ADGroupMember -Identity $DLCommonRW -ErrorAction SilentlyContinue | `
                Where-Object { $_.SamAccountName -eq $ManagerGroupName }
            
            if (-not $IsMember) {
                try {
                    Add-ADGroupMember -Identity $DLCommonRW -Members $ManagerGroup -Confirm:$false
                    Write-Host "  ✓ $ManagerGroupName -> DL_Commun_RW" -ForegroundColor Green
                } catch {
                    $ErrorMsg = $_.Exception.Message
                    Write-Host "  ✗ Erreur ajout a DL_Commun_RW : $ErrorMsg" -ForegroundColor Red
                }
            } else {
                Write-Host "  ✓ $ManagerGroupName deja dans DL_Commun_RW" -ForegroundColor Gray
            }
        }
    }
} else {
    Write-Host "  ✗ DL_Commun_RW non trouve" -ForegroundColor Red
}

# --- RESUME ---
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "AJOUT MANAGERS COMPLETE!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nResume des permissions:" -ForegroundColor Cyan
Write-Host "  ✓ Managers d'Informatique → ecrire dans Dev/HotLine/Systemes" -ForegroundColor Green
Write-Host "  ✓ Managers de Finances → ecrire dans Comptabilite/Investissements" -ForegroundColor Green
Write-Host "  ✓ Managers de Ressources humaines → ecrire dans Gestion/Recrutement" -ForegroundColor Green
Write-Host "  ✓ ... (même logique pour tous les depts)" -ForegroundColor Green
Write-Host "  ✓ TOUS les managers → ecrire dans Commun" -ForegroundColor Green

Write-Host "`nProchaine etape: Ajouter les GG_[SubDept] aux DL_[SubDept]_R (lecture)" -ForegroundColor Yellow
Write-Host "`nFait! 🎯`n" -ForegroundColor Green
