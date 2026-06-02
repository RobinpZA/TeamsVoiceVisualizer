function Resolve-VoiceTargetName {
    <#
    .SYNOPSIS
        Resolves a Teams voice call target ID to a human-readable display name.
    .DESCRIPTION
        Given a target ID (GUID for User/ApplicationEndpoint, or phone number for
        ExternalPstn), returns the display name. Uses an internal cache to minimize
        repeated Get-CsOnlineUser calls.
    .PARAMETER Id
        The target identity (GUID or phone number).
    .PARAMETER Type
        The target type (User, ApplicationEndpoint, ExternalPstn, etc.).
    .PARAMETER NameCache
        A reference to a hashtable used for caching resolved names.
    .EXAMPLE
        Resolve-VoiceTargetName -Id '12345678-...' -Type 'User' -NameCache ([ref]$cache)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Id,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Type,

        [Parameter(Mandatory)]
        [ref]$NameCache
    )

    if (-not $Id) { return $null }
    if (-not $Type) { return $Id }

    # Phone numbers — return as-is, stripping tel: prefix
    if ($Type -eq 'ExternalPstn' -or $Id -match '^tel:' -or $Id -match '^\+\d') {
        return $Id -replace '^tel:', ''
    }

    # Check cache
    if ($NameCache.Value.ContainsKey($Id)) {
        return $NameCache.Value[$Id]
    }

    # HuntGroup = Teams internal type for Call Queue targets
    if ($Type -eq 'HuntGroup') {
        try {
            $cq = Get-CsCallQueue -Identity $Id -ErrorAction SilentlyContinue
            if ($cq -and -not [string]::IsNullOrWhiteSpace([string]$cq.Name)) {
                $NameCache.Value[$Id] = [string]$cq.Name
                return $NameCache.Value[$Id]
            }
        } catch {
            Write-Verbose "Resolve-VoiceTargetName: Could not resolve HuntGroup (CQ) '$Id': $_"
        }
    }

    # ApplicationEndpoint = resource accounts — Get-CsOnlineApplicationInstance is purpose-built
    # for these and reliably returns DisplayName even when Get-CsOnlineUser does not.
    if ($Type -eq 'ApplicationEndpoint') {
        try {
            $appInst = Get-CsOnlineApplicationInstance -Identity $Id -ErrorAction SilentlyContinue
            if ($appInst -and -not [string]::IsNullOrWhiteSpace([string]$appInst.DisplayName)) {
                $NameCache.Value[$Id] = [string]$appInst.DisplayName
                return $NameCache.Value[$Id]
            }
        } catch {
            Write-Verbose "Resolve-VoiceTargetName: Could not resolve ApplicationEndpoint '$Id' via Get-CsOnlineApplicationInstance: $_"
        }
    }

    # Users and resource accounts via Get-CsOnlineUser (covers both in Teams PS 6.x+)
    try {
        $user = Get-CsOnlineUser -Identity $Id -ErrorAction SilentlyContinue
        if ($user) {
            $name = [string]$user.DisplayName
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$user.UserPrincipalName }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $Id }
            $NameCache.Value[$Id] = $name
            return $name
        }
    } catch {
        Write-Verbose "Resolve-VoiceTargetName: Could not resolve '$Id' (type: $Type) via Get-CsOnlineUser: $_"
    }

    # Last-resort: M365 Groups (shared voicemail targets, distribution lists) — try Get-Team.
    # SharedVoicemail targets are often Teams-connected M365 groups.
    try {
        $team = Get-Team -GroupId $Id -ErrorAction SilentlyContinue
        if ($team -and -not [string]::IsNullOrWhiteSpace([string]$team.DisplayName)) {
            $NameCache.Value[$Id] = [string]$team.DisplayName
            return $NameCache.Value[$Id]
        }
    } catch {
        Write-Verbose "Resolve-VoiceTargetName: Could not resolve '$Id' (type: $Type) via Get-Team: $_"
    }

    # Final fallback
    $NameCache.Value[$Id] = $Id
    return $Id
}