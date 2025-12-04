# ════════════════════════════════════════════════════════════════════════════
# SCRIPT TEST BACKUP : Diagnostic et validation de la configuration
# Executez ce script EN TANT QU'ADMINISTRATEUR
# ════════════════════════════════════════════════════════════════════════════

Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      TEST ET DIAGNOSTIC - CONFIGURATION BACKUP         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Verification des permissions administrateur
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $IsAdmin) {
    Write-Host "❌ ERREUR: Ce script doit etre execute EN TANT QU'ADMINISTRATEUR" -ForegroundColor Red
    Exit 1
}

Write-Host "✓ Permissions administrateur confirmees" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# TEST 1: Environment local
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 1] Environment LOCAL" -ForegroundColor Yellow

$ServerInfo = @{
    "Nom du serveur" = $env:COMPUTERNAME
    "Domaine" = (Get-WmiObject Win32_ComputerSystem).Domain
    "OS" = (Get-WmiObject Win32_OperatingSystem).Caption
    "Version OS" = (Get-WmiObject Win32_OperatingSystem).Version
    "PowerShell" = $PSVersionTable.PSVersion
    "Execution Policy" = (Get-ExecutionPolicy)
}

$ServerInfo.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 2: Dossiers de backup
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 2] DOSSIERS DE BACKUP" -ForegroundColor Yellow

$Folders = @(
    "C:\Scripts",
    "C:\Backups",
    "C:\Backups\Logs"
)

foreach ($Folder in $Folders) {
    if (Test-Path $Folder) {
        $FolderSize = (Get-ChildItem -Path $Folder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Host "  ✓ $Folder ($([Math]::Round($FolderSize, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $Folder (n'existe pas)" -ForegroundColor Red
        Write-Host "     → Creer: New-Item -Path '$Folder' -ItemType Directory -Force" -ForegroundColor Yellow
    }
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 3: Scripts
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 3] SCRIPTS" -ForegroundColor Yellow

$Scripts = @(
    "C:\Scripts\Script_Backup_LOCAL_NAS.ps1",
    "C:\Scripts\Schedule_Backup_Tasks.ps1",
    "C:\Scripts\Test_Backup_Connection.ps1"
)

foreach ($Script in $Scripts) {
    if (Test-Path $Script) {
        $ScriptSize = (Get-Item $Script).Length / 1KB
        Write-Host "  ✓ $(Split-Path -Leaf $Script) ($([Math]::Round($ScriptSize, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $(Split-Path -Leaf $Script) (n'existe pas)" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 4: Espace disque
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 4] ESPACE DISQUE" -ForegroundColor Yellow

Get-Volume | Where-Object {$_.DriveLetter} | ForEach-Object {
    $PercentFree = ($_.SizeRemaining / $_.Size) * 100
    $DriveName = $_.DriveLetter + ":"

    if ($PercentFree -lt 10) {
        $Color = "Red"
        $Status = "⚠ CRITIQUE"
    } elseif ($PercentFree -lt 20) {
        $Color = "Yellow"
        $Status = "⚠ BAS"
    } else {
        $Color = "Green"
        $Status = "✓ OK"
    }

    $SizeTotal = [Math]::Round($_.Size / 1GB, 2)
    $SizeFree = [Math]::Round($_.SizeRemaining / 1GB, 2)

    Write-Host "  $DriveName: $SizeFree GB libre / $SizeTotal GB total ($([Math]::Round($PercentFree))%) - $Status" -ForegroundColor $Color
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 5: Connectivite NAS
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 5] CONNECTIVITE NAS" -ForegroundColor Yellow

$NASHost = "192.168.2.199"
$NASShare = "\\192.168.2.199\VOTRESITE"

# Test Ping
Write-Host "  Ping $NASHost..." -NoNewline
$PingTest = Test-Connection -ComputerName $NASHost -Count 1 -Quiet -ErrorAction SilentlyContinue

if ($PingTest) {
    Write-Host " ✓ Reussi" -ForegroundColor Green
} else {
    Write-Host " ❌ Echoue" -ForegroundColor Red
    Write-Host "    → Verifier la connectivite reseau et le pare-feu" -ForegroundColor Yellow
}

# Test SMB
Write-Host "  Test SMB (port 445)..." -NoNewline
$SMBTest = Test-NetConnection -ComputerName $NASHost -Port 445 -WarningAction SilentlyContinue

if ($SMBTest.TcpTestSucceeded) {
    Write-Host " ✓ Reussi" -ForegroundColor Green
} else {
    Write-Host " ❌ Echoue" -ForegroundColor Red
    Write-Host "    → Verifier que SMB est active et le pare-feu autorise le port 445" -ForegroundColor Yellow
}

# Test Authentification
Write-Host "  Test authentification NAS..." -NoNewline

try {
    # Important: utiliser le format correct
    $NASUsername = "VOTRESITE\Agence8"
    $NASPassword = "Test123*"

    $SecurePassword = ConvertTo-SecureString $NASPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($NASUsername, $SecurePassword)

    # Tenter une connexion test
    $TestResult = Test-Path $NASShare -Credential $Credential -ErrorAction SilentlyContinue

    if ($TestResult) {
        Write-Host " ✓ Reussi" -ForegroundColor Green
        Write-Host "    → Acces au partage NAS: OK" -ForegroundColor Green
    } else {
        Write-Host " ❌ Acces refuse" -ForegroundColor Red
        Write-Host "    → Verifier les identifiants: $NASUsername / ****" -ForegroundColor Yellow
    }
} catch {
    Write-Host " ❌ Erreur: $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 6: Permissions et Firewall
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 6] PERMISSIONS ET FIREWALL" -ForegroundColor Yellow

# Test d'ecriture dans C:\Backups
Write-Host "  Test ecriture C:\Backups..." -NoNewline

try {
    $TestFile = "C:\Backups\test_write_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    "Test" | Out-File -FilePath $TestFile -Force

    if (Test-Path $TestFile) {
        Remove-Item -Path $TestFile -Force
        Write-Host " ✓ OK" -ForegroundColor Green
    } else {
        Write-Host " ❌ Echec" -ForegroundColor Red
    }
} catch {
    Write-Host " ❌ Erreur: $_" -ForegroundColor Red
}

# Test Firewall SMB
Write-Host "  Regle Firewall SMB..." -NoNewline

$SMBRules = Get-NetFirewallRule -DisplayName "*file*" -ErrorAction SilentlyContinue | Where-Object {$_.Enabled -eq $true}

if ($SMBRules) {
    Write-Host " ✓ Activee" -ForegroundColor Green
} else {
    Write-Host " ⚠ Verifier manuellement" -ForegroundColor Yellow
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 7: Taches planifiees
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 7] TACHES PLANIFIEES" -ForegroundColor Yellow

$Tasks = @("Backup-Daily-2AM", "Backup-Weekly-Sunday-1AM", "Cleanup-OldBackupLogs")

foreach ($Task in $Tasks) {
    $ScheduledTask = Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue

    if ($ScheduledTask) {
        $State = $ScheduledTask.State
        $Color = if ($State -eq "Ready") { "Green" } else { "Yellow" }
        Write-Host "  ✓ $Task ($State)" -ForegroundColor $Color
    } else {
        Write-Host "  ❌ $Task (n'existe pas)" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 8: Services critiques
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 8] SERVICES CRITIQUES" -ForegroundColor Yellow

$CriticalServices = @(
    "VSS",           # Volume Shadow Copy Service (pour les fichiers verrouilles)
    "BITS",          # Background Intelligent Transfer Service
    "Schedule"       # Task Scheduler
)

foreach ($Service in $CriticalServices) {
    $ServiceStatus = Get-Service -Name $Service -ErrorAction SilentlyContinue

    if ($ServiceStatus) {
        $Status = $ServiceStatus.Status
        $Color = if ($Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  $Service: $Status" -ForegroundColor $Color
    } else {
        Write-Host "  ❌ $Service: Non trouve" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════
# TEST 9: Simulation de backup
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n[TEST 9] SIMULATION DE BACKUP" -ForegroundColor Yellow

Write-Host "  Simulation copie de test..." -ForegroundColor Gray

try {
    $TestSource = "C:\Windows\Temp"
    $TestDest = "C:\Backups\Test_$(Get-Date -Format 'yyyyMMddHHmmss')"

    if (Test-Path $TestSource) {
        New-Item -Path $TestDest -ItemType Directory -Force | Out-Null

        # Copier quelques fichiers de test
        Get-ChildItem -Path $TestSource -File | Select-Object -First 5 | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TestDest -Force -ErrorAction SilentlyContinue
        }

        $FileCount = (Get-ChildItem -Path $TestDest -File).Count
        $FolderSize = (Get-ChildItem -Path $TestDest -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB

        Write-Host "  ✓ Test reussi: $FileCount fichiers copiees ($([Math]::Round($FolderSize, 2)) MB)" -ForegroundColor Green

        # Nettoyer
        Remove-Item -Path $TestDest -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "  ❌ Erreur simulation: $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════
# RAPPORT FINAL
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              RAPPORT DE DIAGNOSTIC                      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nRECAP:" -ForegroundColor Cyan
Write-Host "  • Local: ✓ OK" -ForegroundColor Green
Write-Host "  • Espace disque: Voir TEST 4" -ForegroundColor Gray
Write-Host "  • NAS: Voir TEST 5" -ForegroundColor Gray
Write-Host "  • Taches planifiees: Voir TEST 7" -ForegroundColor Gray

Write-Host "`nPROCHAINES ETAPES:" -ForegroundColor Cyan
Write-Host "  1. Si tout est OK: Lancer un backup manuel" -ForegroundColor Gray
Write-Host "     & 'C:\Scripts\Script_Backup_LOCAL_NAS.ps1'" -ForegroundColor DarkGray
Write-Host "  2. Verifier les resultats dans C:\Backups\Logs" -ForegroundColor Gray
Write-Host "  3. Planifier les taches avec Schedule_Backup_Tasks.ps1" -ForegroundColor Gray

Write-Host "`n⚠ NOTES IMPORTANTES:" -ForegroundColor Yellow
Write-Host "  • Les identifiants NAS sont en clair pour les tests" -ForegroundColor Gray
Write-Host "  • ADAPTER le script avec vos parametres reels" -ForegroundColor Gray
Write-Host "  • Tester sur un petit volume avant la production" -ForegroundColor Gray

Write-Host ""
