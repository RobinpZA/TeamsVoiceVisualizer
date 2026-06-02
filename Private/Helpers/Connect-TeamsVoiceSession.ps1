function Connect-TeamsVoiceSession {
    <#
    .SYNOPSIS
        Ensures a connection to the MicrosoftTeams module is established.
    .DESCRIPTION
        Checks for an existing Teams connection. If none is found, it
        attempts to connect using the authenticated context.
        Returns $true if connected, throws on failure.
    .EXAMPLE
        Connect-TeamsVoiceSession
    #>
    [CmdletBinding()]
    param()

    try {
        # Check if already connected by attempting a lightweight call
        $null = Get-CsTenant -ErrorAction Stop
        Write-Verbose 'TeamsVoiceVisualizer: Already connected to MicrosoftTeams.'
        return $true
    } catch {
        Write-Verbose 'TeamsVoiceVisualizer: No active Teams session. Attempting Connect-MicrosoftTeams...'
        try {
            Connect-MicrosoftTeams -ErrorAction Stop
            Write-Verbose 'TeamsVoiceVisualizer: Connected successfully.'
            return $true
        } catch {
            throw "Failed to connect to MicrosoftTeams. Please run 'Connect-MicrosoftTeams' manually. Error: $($_.Exception.Message)"
        }
    }
}