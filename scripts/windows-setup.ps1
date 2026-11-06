$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:RDP_PASSWORD)) { throw 'RDP_PASSWORD missing.' }
# Windows local accounts are subject to password complexity policy.
# Validate before trying New-LocalUser; never print the password.
$p = $env:RDP_PASSWORD
if ($p.Length -lt 14 -or
    $p -cnotmatch '[A-Z]' -or
    $p -cnotmatch '[a-z]' -or
    $p -notmatch '[0-9]' -or
    $p -notmatch '[^A-Za-z0-9]' -or
    $p -match '(?i)rdpuser') {
    throw 'RDP_PASSWORD does not meet recommended Windows policy: at least 14 characters, uppercase, lowercase, number, symbol, and must not contain rdpuser. Update the GitHub Actions secret.'
}

$tailIp = (tailscale ip -4 | Select-Object -First 1).Trim()
if ($tailIp -notmatch '^100\.') { throw 'Tailscale IP not found.' }

$secure = ConvertTo-SecureString $env:RDP_PASSWORD -AsPlainText -Force
$existingUser = Get-LocalUser -Name 'rdpuser' -ErrorAction SilentlyContinue
if ($existingUser) {
    Set-LocalUser -Name 'rdpuser' -Password $secure
} else {
    New-LocalUser -Name 'rdpuser' -Password $secure -AccountNeverExpires -PasswordNeverExpires -Description 'Temporary RDP user for GitHub Actions' | Out-Null
}
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'rdpuser' -ErrorAction SilentlyContinue
# Allow GUI applications launched by rdpuser to request administrator privileges.
# Resolve the built-in group via its SID so this works on localized Windows.
$administratorsGroup = (Get-LocalGroup -SID 'S-1-5-32-544').Name
$rdpUser = Get-LocalUser -Name 'rdpuser'
$isAdmin = @(Get-LocalGroupMember -Group $administratorsGroup | Where-Object {
    $_.SID -eq $rdpUser.SID
}).Count -gt 0
if (-not $isAdmin) {
    Add-LocalGroupMember -Group $administratorsGroup -Member 'rdpuser' -ErrorAction Stop
}
$isAdmin = @(Get-LocalGroupMember -Group $administratorsGroup | Where-Object {
    $_.SID -eq $rdpUser.SID
}).Count -gt 0
if (-not $isAdmin) {
    throw 'Could not add rdpuser to the local Administrators group.'
}
Write-Host 'rdpuser is a member of local Administrators.'


$terminalServer = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpTcp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $terminalServer -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path $rdpTcp -Name 'UserAuthentication' -Value 1

# Disable default permissive Remote Desktop rules. Limit inbound TCP RDP
# to this runner's Tailscale IPv4 address and Tailnet source address space.
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Get-NetFirewallRule -Name 'GitHubActions-Tailscale-RDP' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name 'GitHubActions-Tailscale-RDP' -DisplayName 'RDP - only over Tailscale' -Direction Inbound -Protocol TCP -LocalPort 3389 -LocalAddress $tailIp -RemoteAddress '100.64.0.0/10' -Action Allow -Profile Any | Out-Null

Set-Service -Name 'TermService' -StartupType Automatic
Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$listener = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    throw 'Windows RDP did not listen on TCP 3389. The GitHub Windows image may disallow Remote Desktop.'
}
Write-Host 'Windows RDP configured; connect over the Tailscale address only.'
