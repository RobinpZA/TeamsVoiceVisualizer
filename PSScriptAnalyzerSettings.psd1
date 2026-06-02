@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Module is a report generator — Write-Host is used for user feedback
        'PSAvoidUsingWriteHost',
        # Graph-building functions are internal; ShouldProcess is not applicable
        'PSUseShouldProcessForStateChangingFunctions',
        # Plural nouns (AutoAttendants, CallQueues) reflect resource collections
        'PSUseSingularNouns',
        # Module requires PowerShell 7.2 which reads UTF-8 without BOM natively
        'PSUseBOMForUnicodeEncodedFile'
    )
}