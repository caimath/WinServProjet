$LocalServerName = $env:COMPUTERNAME
$LocalDomain = (Get-WmiObject Win32_ComputerSystem).Domain

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "SCRIPT DE SAUVEGARDE - BACKUP LOCAL 2025" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "Serveur: $LocalServerName" -ForegroundColor Yellow
Write-Host "Domaine: $LocalDomain" -ForegroundColor Yellow
Write-Host ""

$BackupDirs = @(
    "C:\Windows\SYSVOL",
    "C:\Windows\NTDS",
    "C:\inetpub",
    "C:\Share"
)

$LocalBackupPath = "C:\Backups"
$LogPath = "C:\Backups\Logs"
$LogFile = "$LogPath\Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
$BackupSummary = "$LogPath\BackupSummary_$(Get-Date -Format 'yyyy-MM-dd').csv"

$RetentionDays = 7
$DeleteOldBackups = $true

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")][string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    switch ($Level) {
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogEntry -ForegroundColor Red }
        default   { Write-Host $LogEntry -ForegroundColor Gray }
    }
    Add-Content -Path $LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}

function Initialize-BackupEnvironment {
    Write-Log "Initialisation..." "INFO"
    if (-not (Test-Path $LocalBackupPath)) {
        New-Item -Path $LocalBackupPath -ItemType Directory -Force | Out-Null
        Write-Log "Dossier local cree: $LocalBackupPath" "SUCCESS"
    }
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        Write-Log "Dossier logs cree: $LogPath" "SUCCESS"
    }
    Write-Log "Environnement initialise" "SUCCESS"
}

function Get-BackupFolderSize {
    param([string]$Path)
    if (Test-Path $Path) {
        $Size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return [Math]::Round($Size / 1GB, 2)
    }
    return 0
}

function Remove-OldBackups {
    param([string]$BackupPath, [int]$Days)
    Write-Log "Nettoyage (> $Days jours)..." "INFO"
    $CutoffDate = (Get-Date).AddDays(-$Days)
    $DeletedCount = 0
    try {
        Get-ChildItem -Path $BackupPath -Filter "Backup_*" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $CutoffDate } | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            $DeletedCount++
        }
        if ($DeletedCount -gt 0) {
            Write-Log "Nettoyage: $DeletedCount fichiers supprimes" "SUCCESS"
        }
    } catch {
        Write-Log "ERREUR nettoyage: $_" "WARNING"
    }
}

function Create-Backup {
    param([string]$SourcePath, [string]$DestinationPath, [string]$BackupName)
    Write-Log "Sauvegarde: $SourcePath" "INFO"
    try {
        $BackupFolder = "$DestinationPath\$BackupName"
        if (-not (Test-Path $BackupFolder)) {
            New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
        }
        $RobocopyArgs = @($SourcePath, $BackupFolder, "/S", "/E", "/COPY:DAT", "/R:3", "/W:5", "/MT:8", "/LOG:$LogPath\robocopy_$BackupName.log")
        & robocopy $RobocopyArgs | Out-Null
        $BackupSize = Get-BackupFolderSize -Path $BackupFolder
        Write-Log "Backup OK: $BackupName ($BackupSize GB)" "SUCCESS"
        return @{ Name = $BackupName; Path = $BackupFolder; Size = $BackupSize; Timestamp = Get-Date; Status = "SUCCESS" }
    } catch {
        Write-Log "ERREUR backup $SourcePath : $_" "ERROR"
        return @{ Name = $BackupName; Status = "FAILED"; Error = $_ }
    }
}

function Export-BackupSummary {
    param([array]$BackupResults)
    Write-Log "Export resume..." "INFO"
    try {
        $Summary = @()
        foreach ($Result in $BackupResults) {
            $Summary += [PSCustomObject]@{
                Serveur = $LocalServerName
                Domaine = $LocalDomain
                BackupName = $Result.Name
                Chemin = $Result.Path
                TailleGB = $Result.Size
                Timestamp = $Result.Timestamp
                Status = $Result.Status
                Erreur = if ($Result.Error) { $Result.Error.ToString() } else { "N/A" }
            }
        }
        $Summary | Export-Csv -Path $BackupSummary -Delimiter ";" -Encoding UTF8 -NoTypeInformation -Append
        Write-Log "Resume exporte" "SUCCESS"
    } catch {
        Write-Log "ERREUR export: $_" "WARNING"
    }
}

$StartTime = Get-Date
$BackupResults = @()

Write-Log "========================================" "INFO"
Write-Log "Demarrage de la sauvegarde LOCAL" "INFO"
Write-Log "Serveur: $LocalServerName" "INFO"
Write-Log "Domaine: $LocalDomain" "INFO"
Write-Log "========================================" "INFO"

Initialize-BackupEnvironment

Write-Log "PHASE 1: Sauvegarde LOCALE" "INFO"
Write-Host ""
Write-Host "[PHASE 1] Sauvegarde LOCALE" -ForegroundColor Cyan
Write-Host ""

foreach ($Dir in $BackupDirs) {
    if (Test-Path $Dir) {
        $FolderName = Split-Path -Leaf $Dir
        $BackupName = "Backup_$FolderName`_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
        $Result = Create-Backup -SourcePath $Dir -DestinationPath $LocalBackupPath -BackupName $BackupName
        $BackupResults += $Result
        Start-Sleep -Seconds 2
    }
}

if ($DeleteOldBackups) {
    Remove-OldBackups -BackupPath $LocalBackupPath -Days $RetentionDays
}

Write-Log "PHASE 2: Statistiques" "INFO"
Write-Host ""
Write-Host "[PHASE 2] Calcul des statistiques" -ForegroundColor Cyan
Write-Host ""

$TotalLocalBackupSize = Get-BackupFolderSize -Path $LocalBackupPath
$TotalBackupCount = ($BackupResults | Where-Object { $_.Status -eq "SUCCESS" }).Count
$FailedBackupCount = ($BackupResults | Where-Object { $_.Status -eq "FAILED" }).Count

Export-BackupSummary -BackupResults $BackupResults

$EndTime = Get-Date
$Duration = New-TimeSpan -Start $StartTime -End $EndTime

Write-Log "========================================" "INFO"
Write-Log "RESUME DE SAUVEGARDE" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Serveur: $LocalServerName" "INFO"
Write-Log "Debut: $StartTime" "INFO"
Write-Log "Fin: $EndTime" "INFO"
Write-Log "Duree: $($Duration.TotalMinutes) minutes" "INFO"
Write-Log "Backups OK: $TotalBackupCount" "SUCCESS"
Write-Log "Backups KO: $FailedBackupCount" "WARNING"
Write-Log "Taille: $TotalLocalBackupSize GB" "INFO"
Write-Log "Chemin: $LocalBackupPath" "INFO"
Write-Log "Log: $LogFile" "INFO"
Write-Log "========================================" "INFO"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "SAUVEGARDE TERMINEES" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Backups OK: $TotalBackupCount" -ForegroundColor Green
Write-Host "Backups KO: $FailedBackupCount" -ForegroundColor Yellow
Write-Host "Taille: $TotalLocalBackupSize GB" -ForegroundColor Green
Write-Host "Chemin: $LocalBackupPath" -ForegroundColor Green
Write-Host ""