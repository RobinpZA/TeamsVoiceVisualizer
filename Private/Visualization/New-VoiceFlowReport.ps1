function New-VoiceFlowReport {
    <#
    .SYNOPSIS
        Packages the voice map portal and a voice model into one self-contained HTML file.
    .DESCRIPTION
        Reads Assets/portal/index.html, inlines every stylesheet (fonts become data: URIs)
        and every script, removes the dev sample model, and embeds the model as JSON in
        the #voice-model script element. The output needs no network access.
    .PARAMETER Model
        The voice model (hashtable or PSCustomObject, see docs/model.md).
    .PARAMETER OutputPath
        Optional. When given, the HTML is written as UTF-8 (no BOM) and the path is returned.
        Otherwise the HTML string is returned.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Model,

        [Parameter()]
        [string]$OutputPath
    )

    $portalRoot = Join-Path $script:ModuleRoot 'Assets/portal'
    $indexPath  = Join-Path $portalRoot 'index.html'
    if (-not (Test-Path -LiteralPath $indexPath)) { throw "Portal page not found: $indexPath" }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $readText = {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Referenced file not found: $Path" }
        [System.IO.File]::ReadAllText($Path, $utf8)
    }

    $html = & $readText $indexPath

    # Dev sample model: drop the whole tag.
    $html = [regex]::Replace($html, '<script\b[^>]*\bdata-dev\b[^>]*>.*?</script>\s*', '', 'Singleline')

    # Stylesheets: inline, with font urls turned into data URIs.
    $html = [regex]::Replace($html, '<link\b[^>]*\brel="stylesheet"[^>]*>', {
        param($m)
        $href = [regex]::Match($m.Value, 'href="([^"]+)"').Groups[1].Value
        $cssPath = [System.IO.Path]::GetFullPath((Join-Path $portalRoot $href))
        $css = & $readText $cssPath
        $cssDir = Split-Path -Parent $cssPath
        $css = [regex]::Replace($css, 'url\(\s*["'']?([^"'')]+?\.woff2)["'']?\s*\)', {
            param($u)
            $fontPath = [System.IO.Path]::GetFullPath((Join-Path $cssDir $u.Groups[1].Value))
            if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) { throw "Referenced file not found: $fontPath" }
            $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fontPath))
            'url("data:font/woff2;base64,' + $b64 + '")'
        })
        '<style>' + "`n" + $css + "`n" + '</style>'
    })

    # Scripts: inline (script text must not contain a literal closing tag).
    $html = [regex]::Replace($html, '<script\b[^>]*\bsrc="([^"]+)"[^>]*>\s*</script>', {
        param($m)
        $jsPath = [System.IO.Path]::GetFullPath((Join-Path $portalRoot $m.Groups[1].Value))
        $js = & $readText $jsPath
        $js = $js -replace '</script', '<\/script'
        '<script>' + "`n" + $js + "`n" + '</script>'
    })

    # Model: EscapeHtml turns < > & ' into \uXXXX so model text can never close the tag.
    $json = ConvertTo-Json -InputObject $Model -Depth 30 -Compress -EscapeHandling EscapeHtml
    $placeholder = '<script type="application/json" id="voice-model"></script>'
    if (-not $html.Contains($placeholder)) { throw "Placeholder not found in ${indexPath}: $placeholder" }
    $html = $html.Replace($placeholder, '<script type="application/json" id="voice-model">' + $json + '</script>')

    # Offline guarantee: no remote src/href may remain.
    if ($html -match '(?i)\b(?:src|href)\s*=\s*["'']\s*https?://') {
        throw 'Report still references a remote resource (src/href with http/https).'
    }

    if ($OutputPath) {
        [System.IO.File]::WriteAllText($OutputPath, $html, $utf8)
        return $OutputPath
    }
    $html
}
