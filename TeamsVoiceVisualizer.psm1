#Requires -Version 7.2

$script:ModuleRoot = $PSScriptRoot

# Dot-source all Private functions
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Recurse -Filter '*.ps1' -File |
        ForEach-Object {
            try   { . $_.FullName }
            catch { Write-Warning "Failed to import: $($_.Name) - $_" }
        }
}

# Dot-source all Public functions
$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Recurse -Filter '*.ps1' -File |
        ForEach-Object {
            try   { . $_.FullName }
            catch { Write-Warning "Failed to import: $($_.Name) - $_" }
        }
}