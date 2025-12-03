# ════════════════════════════════════════════════════════════════════════════
# SCRIPT FILTRAGE FSRM - Office + Images Uniquement
# Dossier racine: C:\Share
# Interdit: Tout sauf Office et Images
# Action: Bloquer + Event Log
# ════════════════════════════════════════════════════════════════════════════

$RootPath = "C:\Share"
$Domain = "Belgique.lan"

Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "FILTRAGE FSRM - C:\Share" -ForegroundColor Cyan
Write-Host "Autorise: Office + Images" -ForegroundColor Cyan
Write-Host "Interdit: TOUT LE RESTE" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

# --- 1. IMPORTER MODULE FSRM ---
Write-Host "`n[1/3] Import FSRM..." -ForegroundColor Yellow
Import-Module FileServerResourceManager
Write-Host "Module charge." -ForegroundColor Green

# --- 2. CREER LE GROUPE DE FICHIERS AUTORISE ---
Write-Host "`n[2/3] Creation du groupe de fichiers..." -ForegroundColor Yellow

$GroupName = "Autorises_Office_Images"
$ExistingGroup = Get-FsrmFileGroup -Name $GroupName -ErrorAction SilentlyContinue

if (-not $ExistingGroup) {
    # Extensions OFFICE autorisees
    $OfficeExt = @(
        "*.doc", "*.docx", "*.dot", "*.dotx",
        "*.xls", "*.xlsx", "*.xlt", "*.xltx",
        "*.ppt", "*.pptx", "*.pot", "*.potx",
        "*.odt", "*.ods", "*.odp",
        "*.rtf", "*.txt", "*.pdf"
    )
    
    # Extensions IMAGES autorisees
    $ImageExt = @(
        "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp",
        "*.tiff", "*.tif", "*.webp", "*.svg", "*.ico",
        "*.psd", "*.raw"
    )
    
    # Combiner
    $AllowedExt = $OfficeExt + $ImageExt
    
    # Creer le groupe
    New-FsrmFileGroup -Name $GroupName -IncludePattern $AllowedExt `
        -Description "Fichiers Office et Images autorises sur C:\Share"
    
    Write-Host "Groupe cree: $GroupName" -ForegroundColor Green
    Write-Host "Office ($($OfficeExt.Count) ext) + Images ($($ImageExt.Count) ext)" -ForegroundColor Green
} else {
    Write-Host "Groupe existe deja: $GroupName" -ForegroundColor Gray
}

# --- 3. CREER ET APPLIQUER LE FILTRAGE ---
Write-Host "`n[3/3] Application du filtrage sur C:\Share..." -ForegroundColor Yellow

# Action 1: Event Log (Avertissement)
$ActionEventLog = New-FsrmAction -Type EventLog -EventType Warning `
    -Body "FSRM BLOQUE: Tentative de depot de fichier non autorise. Extension interdite (Office et Images uniquement)."

# Creer le filtrage HARD (Bloque = Impossible a telecharger)
function Apply-FileScreenRecursive {
    param(
        [string]$Path
    )
    
    # Verifier si filtrage existe
    $Existing = Get-FsrmFileScreen -Path $Path -ErrorAction SilentlyContinue
    
    if (-not $Existing) {
        New-FsrmFileScreen -Path $Path `
            -IncludeGroup $GroupName `
            -BlockingType Hard `
            -Action $ActionEventLog
        Write-Host "Filtrage applique: $Path"
    }
    
    # Appliquer recursivement sur sous-dossiers
    $SubFolders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    foreach ($SubFolder in $SubFolders) {
        Apply-FileScreenRecursive -Path $SubFolder.FullName
    }
}

Apply-FileScreenRecursive -Path $RootPath

# --- BILAN ---
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "FILTRAGE TERMINE" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nFichiers AUTORISES:" -ForegroundColor Green
Write-Host "OFFICE: .doc .docx .xls .xlsx .ppt .pptx .odt .ods .odp .rtf .txt .pdf" -ForegroundColor Green
Write-Host "IMAGES: .jpg .jpeg .png .gif .bmp .tiff .webp .svg .ico .psd .raw" -ForegroundColor Green

Write-Host "`nComportement:" -ForegroundColor Cyan
Write-Host "✓ Mode HARD: Fichiers interdits BLOQUES (impossible a telecharger)" -ForegroundColor Yellow
Write-Host "✓ Event Log: Chaque tentative enregistree dans Windows Event Viewer" -ForegroundColor Yellow
Write-Host "✓ Recursif: Filtrage applique sur C:\Share et tous les sous-dossiers" -ForegroundColor Yellow

Write-Host "`nPour TESTER:" -ForegroundColor Cyan
Write-Host "1. Essayer de copier un .exe ou .zip dans C:\Share\..." -ForegroundColor Gray
Write-Host "   -> Doit afficher 'Acces refuse'" -ForegroundColor Gray
Write-Host "2. Verifier l'Event Log:" -ForegroundColor Gray
Write-Host "   -> Event Viewer > Windows Logs > System (Source: FSRM)" -ForegroundColor Gray

Write-Host "`nPour VOIR LES FILTRAGES:" -ForegroundColor Cyan
Write-Host "1. Gestionnaire Ressources Serveur > Gestion des fichiers > Ecrans de fichiers" -ForegroundColor Gray
Write-Host "2. Chercher les entrees avec le chemin C:\Share" -ForegroundColor Gray

Write-Host "════════════════════════════════════════" -ForegroundColor Green
