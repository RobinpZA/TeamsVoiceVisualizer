function Get-VoiceResourceAccountMap {
    <#
    .SYNOPSIS
        Builds a reverse lookup of Auto Attendant / Call Queue id to the resource
        account (application instance) object ids that front it.
    .DESCRIPTION
        Thin wrapper over Get-VoiceResourceAccountData that returns only the
        configuration-id -> @(ra object ids) map. Kept so existing callers work.
    .EXAMPLE
        $map = Get-VoiceResourceAccountMap
        $map['11111111-2222-3333-4444-555555555555']  # -> @('<ra-guid>', ...)
    .NOTES
        Keys are lower-cased so callers can look up with a normalized identity.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return (Get-VoiceResourceAccountData).Map
}
