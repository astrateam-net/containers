# devget entrypoint — the stock gateway entrypoint plus the bits it doesn't expose
# as env vars but our authority model needs:
#   - GATEWAY_ID  : a fixed gateway Id (so the authority's jet_gw_id matches; the
#                   stock entrypoint never sets an Id and the gateway generates none)
#   - ENABLE_UNSTABLE / kerberos : credential-injection Kerberos path for DOMAIN targets
#                   (added in a later step; NTLM/domainless targets don't need it)
#
# Sensitive inputs (provisioner keys, TLS cert/key, cert + webapp passwords) accept a
# <NAME>_FILE variant pointing at a Docker secret (/run/secrets/<n>) or a bind-mounted
# file (e.g. an acme.sh-managed cert), on top of the legacy <NAME>_B64 / <NAME> env.
# _FILE wins, so secrets never have to live in the environment. See Resolve-Secret* below.
#
# Everything else is byte-for-byte the stock entrypoint logic.

Import-Module DevolutionsGateway -ErrorAction Stop

# --- Secret resolution: Docker secrets / bind-mounted files (the _FILE convention) ---
# Priority for any sensitive input NAME: NAME_FILE (a file path) > NAME_B64 > NAME (raw).

# Resolve a sensitive STRING (passwords). Reads NAME_FILE if set (trimming the trailing
# newline a secret file usually carries), else the raw NAME env. Returns $null if neither.
function Resolve-SecretString {
    param([Parameter(Mandatory)][string]$Name)
    $path = [Environment]::GetEnvironmentVariable("${Name}_FILE")
    if ($path) {
        if (-not (Test-Path $path)) { throw "${Name}_FILE points at '$path' which does not exist" }
        return ([IO.File]::ReadAllText($path)).TrimEnd("`r", "`n")
    }
    return [Environment]::GetEnvironmentVariable($Name)
}

# Resolve a sensitive FILE (PEM keys/certs). Returns @{ Path; Temp } or $null:
#   NAME_FILE -> used in place (Temp=$false; a mounted secret/cert — never deleted).
#   NAME_B64  -> decoded to $TmpPath (Temp=$true; cleaned up after import).
function Resolve-SecretFile {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$TmpPath)
    $path = [Environment]::GetEnvironmentVariable("${Name}_FILE")
    if ($path) {
        if (-not (Test-Path $path)) { throw "${Name}_FILE points at '$path' which does not exist" }
        return @{ Path = $path; Temp = $false }
    }
    $b64 = [Environment]::GetEnvironmentVariable("${Name}_B64")
    if ($b64) {
        try { [IO.File]::WriteAllBytes($TmpPath, [Convert]::FromBase64String($b64)) }
        catch { throw "Failed to decode ${Name}_B64: $_" }
        return @{ Path = $TmpPath; Temp = $true }
    }
    return $null
}

$Hostname = 'localhost'
$WebPort = 7171
$WebScheme = 'http'
$TcpPort = 8181
$TcpEnabled = $true
$WebAppEnabled = $false
$WebAppAuthentication = 'None'

if ($Env:WEB_SCHEME) { $WebScheme = $Env:WEB_SCHEME }
$ExternalWebScheme = $WebScheme
if ($Env:EXTERNAL_WEB_SCHEME) { $ExternalWebScheme = $Env:EXTERNAL_WEB_SCHEME }
if (Test-Path Env:WEB_PORT) { $WebPort = $Env:WEB_PORT }
if (Test-Path Env:PORT) { $WebPort = $Env:PORT }
$ExternalWebPort = $WebPort
if (Test-Path Env:EXTERNAL_WEB_PORT) { $ExternalWebPort = $Env:EXTERNAL_WEB_PORT }
if (Test-Path Env:HOSTNAME) { $Hostname = $Env:HOSTNAME }
if (Test-Path Env:WEBSITE_HOSTNAME) {
    $Hostname = $Env:WEBSITE_HOSTNAME
    if (Test-Path Env:WEBSITE_INSTANCE_ID) { $ExternalWebScheme = 'https'; $ExternalWebPort = 443 }
}

if ($Env:WEB_APP_ENABLED) {
    try { $WebAppEnabled = [bool]::Parse($Env:WEB_APP_ENABLED) } catch { $WebAppEnabled = $false }
}
if ($WebAppEnabled) { $TcpEnabled = $false }
if ($Env:TCP_ENABLED) {
    try { $TcpEnabled = [bool]::Parse($Env:TCP_ENABLED) } catch { $TcpEnabled = $false }
}
if (Test-Path Env:TCP_PORT) { $TcpPort = $Env:TCP_PORT }
$ExternalTcpPort = $TcpPort
if (Test-Path Env:EXTERNAL_TCP_PORT) { $ExternalTcpPort = $Env:EXTERNAL_TCP_PORT }
$TcpHostname = '*'
if (Test-Path Env:TCP_HOSTNAME) { $TcpHostname = $Env:TCP_HOSTNAME }

# Webapp Custom-auth credentials: username plain, password via the _FILE convention
# (so it can come from a Docker secret). Resolved once, reused for Set-DGatewayUser below.
$WebAppUsername = Resolve-SecretString 'WEB_APP_USERNAME'
$WebAppPassword = Resolve-SecretString 'WEB_APP_PASSWORD'
if ($WebAppUsername -and $WebAppPassword) { $WebAppAuthentication = 'Custom' }
if ($Env:WEB_APP_AUTHENTICATION) { $WebAppAuthentication = $Env:WEB_APP_AUTHENTICATION }

$WebListener = New-DGatewayListener "$WebScheme`://*:$WebPort" "$ExternalWebScheme`://*:$ExternalWebPort"
$TcpListener = New-DGatewayListener "tcp://*:$TcpPort" "tcp://$TcpHostname`:$ExternalTcpPort"
if ($TcpEnabled) { $Listeners = @($WebListener, $TcpListener) } else { $Listeners = @($WebListener) }

$WebApp = New-DGatewayWebAppConfig -Enabled $WebAppEnabled -Authentication $WebAppAuthentication

$ConfigParams = @{
    Hostname  = $Hostname
    Listeners = $Listeners
    WebApp    = $WebApp
}

# devget: a fixed gateway Id so the authority's jet_gw_id matches. Set-DGatewayConfig
# takes -Id [Guid]; the stock entrypoint never sets one.
if (Test-Path Env:GATEWAY_ID) {
    $ConfigParams.Id = [Guid]$Env:GATEWAY_ID
}

Set-DGatewayConfig @ConfigParams

if ($WebAppAuthentication -eq 'Custom') {
    if ($WebAppUsername -and $WebAppPassword) {
        Set-DGatewayUser -Username $WebAppUsername -Password $WebAppPassword
    }
}

if (Test-Path Env:RECORDING_PATH) { Set-DGatewayRecordingPath -RecordingPath $Env:RECORDING_PATH }
if (Test-Path Env:VERBOSITY_PROFILE) { Set-DGatewayConfig -VerbosityProfile $Env:VERBOSITY_PROFILE }

$ProvisionerPublic = Resolve-SecretFile 'PROVISIONER_PUBLIC_KEY' '/tmp/provisioner.pem'
$ProvisionerPrivate = Resolve-SecretFile 'PROVISIONER_PRIVATE_KEY' '/tmp/provisioner.key'

if ($ProvisionerPublic -or $ProvisionerPrivate) {
    Write-Host "Importing provisioner keys..."
    $pubPath = if ($ProvisionerPublic) { $ProvisionerPublic.Path } else { $null }
    $privPath = if ($ProvisionerPrivate) { $ProvisionerPrivate.Path } else { $null }
    Import-DGatewayProvisionerKey -PublicKeyFile $pubPath -PrivateKeyFile $privPath
    foreach ($s in @($ProvisionerPublic, $ProvisionerPrivate)) {
        if ($s -and $s.Temp) { Remove-Item $s.Path -ErrorAction SilentlyContinue | Out-Null }
    }
} else {
    Write-Host "Generating provisioner keys..."
    New-DGatewayProvisionerKeyPair -Force
}

# TLS cert/key: prefer a bind-mounted file (e.g. the acme.sh-managed wildcard the host
# already maintains) or a Docker secret via _FILE; fall back to _B64. NOTE: the gateway
# IMPORTS the cert into its config store at startup, so a renewed cert on the mount is
# picked up on the next container restart.
$TlsCert = Resolve-SecretFile 'TLS_CERTIFICATE' '/tmp/tls-certificate.pem'
$TlsKey = Resolve-SecretFile 'TLS_PRIVATE_KEY' '/tmp/tls-private-key.pem'
$TlsCertificatePassword = Resolve-SecretString 'TLS_CERTIFICATE_PASSWORD'

if ($TlsCert -or $TlsKey) {
    Write-Host "Importing TLS certificate..."
    $certPath = if ($TlsCert) { $TlsCert.Path } else { $null }
    $keyPath = if ($TlsKey) { $TlsKey.Path } else { $null }
    Import-DGatewayCertificate -CertificateFile $certPath -PrivateKeyFile $keyPath -Password $TlsCertificatePassword
    foreach ($s in @($TlsCert, $TlsKey)) {
        if ($s -and $s.Temp) { Remove-Item $s.Path -ErrorAction SilentlyContinue | Out-Null }
    }
}

$Config = Get-DGatewayConfig -NullProperties
if ($WebScheme -eq 'https' -and
    [string]::IsNullOrEmpty($Config.TlsCertificateFile) -and
    [string]::IsNullOrEmpty($Config.TlsPrivateKeyFile)) {
    Write-Host "Generating self-signed TLS certificate for '$Hostname'..."
    $TlsCertificateFile = "/tmp/gateway-$Hostname.pem"
    $TlsPrivateKeyFile = "/tmp/gateway-$Hostname.key"
    $Arguments = @(
        "req", "-x509", "-nodes", "-newkey", "rsa:2048",
        "-keyout", $TlsPrivateKeyFile, "-out", $TlsCertificateFile,
        "-subj", "/CN=$Hostname",
        "-addext", "subjectAltName=DNS:$Hostname,DNS:localhost,IP:127.0.0.1",
        "-days", "1825"
    )
    $Output = & openssl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "OpenSSL failed:`n$Output" }
    Import-DGatewayCertificate -CertificateFile $TlsCertificateFile -PrivateKeyFile $TlsPrivateKeyFile
    Remove-Item @($TlsCertificateFile, $TlsPrivateKeyFile) -ErrorAction SilentlyContinue | Out-Null
}

& "$Env:DGATEWAY_EXECUTABLE_PATH"
[System.Environment]::ExitCode = $LASTEXITCODE
