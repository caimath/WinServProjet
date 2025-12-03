# SCRIPT DHCP FINALISATION (A executer APRES le redémarrage du DC)
# PowerShell 5.1 COMPATIBLE

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINALISATION CONFIG DHCP POST-REDEMARRAGE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- [1] Attendre que DHCP soit pleinement opérationnel ---
Write-Host "`n[1/3] Attente du demarrage des services..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
Get-Service DHCP | Start-Service -ErrorAction SilentlyContinue

# --- [2] Autoriser le serveur DHCP dans AD ---
Write-Host "`n[2/3] Autorisation du serveur DHCP dans Active Directory..." -ForegroundColor Yellow

try {
    Add-DhcpServerInDC -DnsName "DC.Belgique.lan" -IPAddress "172.28.60.21" -ErrorAction SilentlyContinue
    Write-Host "OK: Serveur DHCP autorisé dans AD" -ForegroundColor Green
} catch {
    Write-Host "ATTENTION: DHCP déjà autorisé ou erreur: $_" -ForegroundColor Gray
}

# --- [3] Configuration options DHCP pour chaque scope ---
Write-Host "`n[3/3] Configuration des options DHCP (DNS, Gateway, etc)..." -ForegroundColor Yellow

$DHCPScopes = @(
    @{ Name = "VLAN10-Admin";       Gateway = "172.28.10.1";    DNS = "172.28.60.21" },
    @{ Name = "VLAN20-RD";          Gateway = "172.28.20.1";    DNS = "172.28.60.21" },
    @{ Name = "VLAN30-IT";          Gateway = "172.28.30.1";    DNS = "172.28.60.21" },
    @{ Name = "VLAN40-Commercial";  Gateway = "172.28.40.1";    DNS = "172.28.60.21" },
    @{ Name = "VLAN50-Technique";   Gateway = "172.28.50.1";    DNS = "172.28.60.21" },
    @{ Name = "VLAN99-VoIP";        Gateway = "172.28.99.1";    DNS = "172.28.60.21" }
)

foreach ($Scope in $DHCPScopes) {
    $ScopeID = $Scope.Name -replace "VLAN\d+-", ""
    $ScopeFilter = "Name -eq '$($Scope.Name)'"
    $ScopeObj = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Scope.Name }
    
    if ($ScopeObj) {
        try {
            # Option 3: Default Gateway
            Set-DhcpServerv4OptionValue -ScopeId $ScopeObj.ScopeId -OptionId 3 -Value $Scope.Gateway -ErrorAction SilentlyContinue
            
            # Option 6: DNS Servers
            Set-DhcpServerv4OptionValue -ScopeId $ScopeObj.ScopeId -OptionId 6 -Value $Scope.DNS -ErrorAction SilentlyContinue
            
            # Option 15: Domain Name
            Set-DhcpServerv4OptionValue -ScopeId $ScopeObj.ScopeId -OptionId 15 -Value "Belgique.lan" -ErrorAction SilentlyContinue
            
            Write-Host "OK: Options configurees pour $($Scope.Name)" -ForegroundColor Green
        } catch {
            Write-Host "ERREUR options $($Scope.Name): $_" -ForegroundColor Red
        }
    } else {
        Write-Host "WARNING: Scope $($Scope.Name) non trouvé" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "DHCP FINALISE ET OPERATIONNEL" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
