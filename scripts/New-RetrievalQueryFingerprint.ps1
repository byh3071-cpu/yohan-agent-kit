#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FingerprintKeyId,
    [ValidatePattern('^[A-Z][A-Z0-9_]{2,63}$')][string]$KeyEnvironmentVariable = 'YOHAN_RETRIEVAL_HMAC_KEY',
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RetrievalEvidence.Common.ps1')

try {
    Assert-SafeFingerprintKeyId -Value $FingerprintKeyId
    $query = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrEmpty($query)) { throw 'Query stdin cannot be empty' }
    if ($query.IndexOf([char]0) -ge 0) { throw 'Query stdin contains a forbidden null character' }
    $key = [Environment]::GetEnvironmentVariable($KeyEnvironmentVariable, [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'Retrieval HMAC key is not configured in the process environment' }
    if ($key.Length -lt 16) { throw 'Retrieval HMAC key is too short' }

    $keyBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($key)
    $queryBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($query)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$keyBytes)
    try { $fingerprint = ([BitConverter]::ToString($hmac.ComputeHash($queryBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hmac.Dispose() }

    $result = [pscustomobject][ordered]@{
        fingerprint_scheme = 'hmac-sha256-v1'
        fingerprint_key_id = $FingerprintKeyId
        query_fingerprint = $fingerprint
    }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Compress)) }
    else { Write-Output "Created hmac-sha256-v1 fingerprint with key id $FingerprintKeyId" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
