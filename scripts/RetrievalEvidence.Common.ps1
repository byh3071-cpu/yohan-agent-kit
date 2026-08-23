#requires -Version 5.1

Set-StrictMode -Version 2.0

$script:RetrievalSchemaPaths = @(
    'memory/retrieval-evidence/schemas/retrieval-learning-candidate.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-outcome-event.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-receipt.schema.json'
) | Sort-Object
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false, $true)

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function ConvertTo-NormalizedLf {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n", [StringComparison]::Ordinal)) { $normalized += "`n" }
    return $normalized
}

function Get-OrdinaryRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = 'Root')

    if (-not [IO.Directory]::Exists($Path)) { throw "$Label must be an existing directory" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $current = $full
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $entry = Get-Item -LiteralPath $current -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label path cannot contain a reparse point" }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -ceq $current) { break }
        $current = $parent.FullName
    }
    return $full
}

function Test-RepoRelativePosixPath {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or $Path -match '[\r\n]') { return $false }
    if (@($Path.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) { return $false }
    return $true
}

function Get-SafeEventLogPath {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind
    )

    $root = Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot'
    $pattern = '^memory/retrieval-evidence/events/' + [Regex]::Escape($Kind) + '-\d{4}-\d{2}\.jsonl$'
    if ($RelativePath -notmatch $pattern -or -not (Test-RepoRelativePosixPath -Path $RelativePath)) { throw "$Kind event log path is not allowed" }
    $target = [IO.Path]::GetFullPath((Join-Path $root $RelativePath.Replace('/', '\')))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "$Kind event log escapes BrainRoot" }
    $parent = Split-Path -Parent $target
    if (-not [IO.Directory]::Exists($parent)) { throw "$Kind event log parent must already exist" }
    $null = Get-OrdinaryRoot -Path $parent -Label "$Kind event log parent"
    if ([IO.File]::Exists($target)) {
        $entry = Get-Item -LiteralPath $target -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Kind event log cannot be a reparse point" }
    }
    return $target
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $git = $null
    foreach ($candidate in @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists([string]$candidate.Source)) { $git = [string]$candidate.Source; break }
    }
    if ([string]::IsNullOrWhiteSpace($git)) { throw 'git.exe is unavailable' }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "$Label is unavailable at the requested Git ref" }
    return [string]::Join("`n", @($output | ForEach-Object { [string]$_ }))
}

function Get-RetrievalContractSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedSchemaDigest
    )

    $contractRoot = Get-OrdinaryRoot -Path $ContractRepositoryRoot -Label 'ContractRepositoryRoot'
    $resolved = (Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('rev-parse', '--verify', "$ContractRef`^{commit}") -Label 'Contract commit').Trim()
    if ($resolved -cne $ContractRef) { throw 'ContractRef must resolve to the exact commit' }

    $indexText = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:memory/retrieval-evidence/index.yaml") -Label 'Retrieval evidence index'
    $contractText = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:memory/core/retrieval-contract.yaml") -Label 'Retrieval contract'
    if ($indexText -notmatch '(?m)^status: active\s*$') { throw 'Retrieval evidence index is not active' }
    if (-not $indexText.Contains("schema_bundle_digest: $ExpectedSchemaDigest")) { throw 'Retrieval evidence index schema digest mismatch' }
    if ($contractText -notmatch '(?m)^  status: active\s*$' -or $contractText -notmatch '(?m)^  implementation_status: implemented\s*$') { throw 'Retrieval evidence contract is not active/implemented' }
    if (-not $contractText.Contains("digest: $ExpectedSchemaDigest")) { throw 'Retrieval contract schema digest mismatch' }
    if ($contractText -notmatch '(?m)^    agent_kit_implementation_ref: [0-9a-f]{40}\s*$') { throw 'Retrieval contract Agent Kit implementation ref missing' }
    foreach ($required in @(
        'persistent_writes: []',
        'persistence: forbidden',
        'writer: yohan-agent-kit',
        'fingerprint_scheme: hmac-sha256-v1',
        'correction_mode: append-only',
        'automatic_query_recording: forbidden',
        'stable_auto_promotion: false'
    )) {
        if (-not $contractText.Contains($required) -and -not $indexText.Contains($required)) { throw "Retrieval contract invariant missing: $required" }
    }

    $bundle = ''
    $schemaByName = @{}
    foreach ($relativePath in $script:RetrievalSchemaPaths) {
        $text = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:$relativePath") -Label $relativePath
        $normalized = ConvertTo-NormalizedLf -Text $text
        $bundle += $relativePath + "`n" + $normalized
        try { $schema = $text | ConvertFrom-Json }
        catch { throw "$relativePath is not valid JSON" }
        if ($schema.type -cne 'object' -or [bool]$schema.additionalProperties -ne $false) { throw "$relativePath must be a closed object schema" }
        $schemaByName[[IO.Path]::GetFileName($relativePath)] = $schema
    }
    $actualDigest = Get-Sha256Hex -Text $bundle
    if ($actualDigest -cne $ExpectedSchemaDigest) { throw 'Pinned schema bundle bytes do not match ExpectedSchemaDigest' }

    return [pscustomobject][ordered]@{
        ContractRef = $ContractRef
        SchemaDigest = $actualDigest
        ReceiptSchema = $schemaByName['retrieval-receipt.schema.json']
        OutcomeSchema = $schemaByName['retrieval-outcome-event.schema.json']
        CandidateSchema = $schemaByName['retrieval-learning-candidate.schema.json']
    }
}

function Assert-AllowedObjectFields {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($null -eq $Value -or $Value -isnot [psobject]) { throw "$Label must be an object" }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $names) {
        if ($Allowed -cnotcontains [string]$name) { throw "$Label field is not allowed: $name" }
    }
    foreach ($name in $Required) {
        if ($names -cnotcontains $name) { throw "$Label required field is missing: $name" }
    }
}

function ConvertFrom-StrictJsonText {
    param([Parameter(Mandatory = $true)][string]$Text, [string]$Label = 'JSON input')

    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Label cannot be empty" }
    try { return $Text | ConvertFrom-Json }
    catch {
        $firstCodePoint = if ($Text.Length -gt 0) { [int][char]$Text[0] } else { -1 }
        throw "$Label is not valid JSON (length=$($Text.Length), first_codepoint=$firstCodePoint, parser=$($_.Exception.GetType().Name))"
    }
}

function Get-StrictUtf8Text {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [string]$Label = 'JSONL')

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw "$Label must be UTF-8 without BOM" }
    try { return $script:Utf8NoBom.GetString($Bytes) }
    catch [Text.DecoderFallbackException] { throw "$Label is not valid UTF-8" }
}

function ConvertFrom-JsonLinesText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$IdProperty, [string]$Label = 'JSONL')

    $rows = New-Object Collections.Generic.List[object]
    $ids = @{}
    foreach ($line in @($Text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $row = $line | ConvertFrom-Json }
        catch { throw "$Label contains invalid JSONL" }
        $property = $row.PSObject.Properties[$IdProperty]
        if ($null -eq $property) { throw "$Label row is missing $IdProperty" }
        $id = [string]$property.Value
        if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,127}$' -or $ids.ContainsKey($id)) { throw "$Label has invalid or duplicate $IdProperty" }
        $ids[$id] = $true
        $rows.Add($row)
    }
    return [pscustomobject][ordered]@{ Rows = $rows.ToArray(); Ids = $ids }
}

function Read-JsonLineLog {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$IdProperty,
        [switch]$RequireExisting
    )

    $target = Get-SafeEventLogPath -BrainRoot $BrainRoot -RelativePath $RelativePath -Kind $Kind
    if (-not [IO.File]::Exists($target)) {
        if ($RequireExisting) { throw "$Kind event log does not exist" }
        return [pscustomobject][ordered]@{ Path = $target; Rows = @(); Ids = @{} }
    }
    $bytes = [IO.File]::ReadAllBytes($target)
    $parsed = ConvertFrom-JsonLinesText -Text (Get-StrictUtf8Text -Bytes $bytes -Label "$Kind event log") -IdProperty $IdProperty -Label "$Kind event log"
    return [pscustomobject][ordered]@{ Path = $target; Rows = $parsed.Rows; Ids = $parsed.Ids }
}

function Add-JsonLineAppendOnly {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$IdProperty,
        [Parameter(Mandatory = $true)]$Value
    )

    $target = Get-SafeEventLogPath -BrainRoot $BrainRoot -RelativePath $RelativePath -Kind $Kind
    $id = [string]$Value.PSObject.Properties[$IdProperty].Value
    $line = [string]($Value | ConvertTo-Json -Depth 20 -Compress)
    $mode = if ([IO.File]::Exists($target)) { [IO.FileMode]::Open } else { [IO.FileMode]::CreateNew }
    $stream = New-Object IO.FileStream($target, $mode, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    try {
        $existingBytes = New-Object byte[] $stream.Length
        $offset = 0
        while ($offset -lt $existingBytes.Length) {
            $read = $stream.Read($existingBytes, $offset, $existingBytes.Length - $offset)
            if ($read -le 0) { throw "Unable to read complete $Kind event log" }
            $offset += $read
        }
        $existingText = Get-StrictUtf8Text -Bytes $existingBytes -Label "$Kind event log"
        $existing = ConvertFrom-JsonLinesText -Text $existingText -IdProperty $IdProperty -Label "$Kind event log"
        if ($existing.Ids.ContainsKey($id)) { throw "Duplicate $IdProperty`: $id" }
        $prefix = if ($existingBytes.Length -gt 0 -and $existingBytes[$existingBytes.Length - 1] -ne 0x0A) { "`n" } else { '' }
        $appendBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($prefix + $line + "`n")
        $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
        $stream.Write($appendBytes, 0, $appendBytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    return $RelativePath
}

function Assert-SafeIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Label)

    if ($Value -notmatch '^[a-z0-9][a-z0-9-]{0,127}$') { throw "$Label is invalid" }
}

function Assert-SafeFingerprintKeyId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$' -or $Value -match '(?i)secret|token|password|credential|api[-_]?key') { throw 'FingerprintKeyId is invalid or secret-like' }
}
