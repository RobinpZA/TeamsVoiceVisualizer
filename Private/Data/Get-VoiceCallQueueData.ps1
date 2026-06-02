function Get-VoiceCallQueueData {
    <#
    .SYNOPSIS
        Retrieves all Call Queues and enriches them with resolved target names
        and structured data suitable for visualization.
    .PARAMETER NameCache
        A reference to a hashtable used for caching resolved target display names.
    .EXAMPLE
        $cache = @{}
        Get-VoiceCallQueueData -NameCache ([ref]$cache)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]$NameCache
    )

    try {
        $cqs = Get-CsCallQueue -ErrorAction Stop
    } catch {
        throw "Failed to retrieve Call Queues: $($_.Exception.Message)"
    }

    $result = @($cqs | ForEach-Object {
        $cq = $_

        # Resolve target names
        $resolveTarget = {
            param($TargetObj)
            if ($TargetObj -and $TargetObj.Id -and [string]$TargetObj.Type) {
                Resolve-VoiceTargetName -Id $TargetObj.Id -Type ([string]$TargetObj.Type) -NameCache $NameCache
            }
            return $null
        }

        $overflowTargetId   = if ($cq.OverflowActionTarget)   { [string]$cq.OverflowActionTarget.Id   } else { $null }
        $overflowTargetType = if ($cq.OverflowActionTarget)   { [string]$cq.OverflowActionTarget.Type } else { $null }
        $timeoutTargetId    = if ($cq.TimeoutActionTarget)    { [string]$cq.TimeoutActionTarget.Id    } else { $null }
        $timeoutTargetType  = if ($cq.TimeoutActionTarget)    { [string]$cq.TimeoutActionTarget.Type  } else { $null }
        $noAgentTargetId    = if ($cq.NoAgentActionTarget)    { [string]$cq.NoAgentActionTarget.Id    } else { $null }
        $noAgentTargetType  = if ($cq.NoAgentActionTarget)    { [string]$cq.NoAgentActionTarget.Type  } else { $null }

        $overflowTargetName = & $resolveTarget $cq.OverflowActionTarget
        $timeoutTargetName  = & $resolveTarget $cq.TimeoutActionTarget
        $noAgentTargetName  = & $resolveTarget $cq.NoAgentActionTarget

        # Agents
        $agentIds = @($cq.Agents | Where-Object { $_ -and $_.ObjectId } | ForEach-Object { [string]$_.ObjectId })
        $distributionListIds = @($cq.DistributionLists | Where-Object { $_ } | ForEach-Object { [string]$_ })
        $oboRaIds = @($cq.OboResourceAccountIds | Where-Object { $_ } | ForEach-Object { [string]$_ })

        # Resolve agent display names
        $agentNames = @($agentIds | ForEach-Object {
            Resolve-VoiceTargetName -Id $_ -Type 'User' -NameCache $NameCache
        })

        # Resolve distribution list names
        $dlNames = @($distributionListIds | ForEach-Object {
            Resolve-VoiceTargetName -Id $_ -Type 'Group' -NameCache $NameCache
        })

        # Resolve OBO resource account names
        $oboRaNames = @($oboRaIds | ForEach-Object {
            Resolve-VoiceTargetName -Id $_ -Type 'ApplicationEndpoint' -NameCache $NameCache
        })

        # Associated resource accounts
        $associatedRAs = @()
        try {
            $assoc = Get-CsOnlineApplicationInstanceAssociation -Identity $cq.Identity -ErrorAction SilentlyContinue
            if ($assoc) {
                $associatedRAs = @($assoc | Where-Object { $_ } | ForEach-Object { [string]$_.ObjectId })
            }
        } catch {
            Write-Verbose "CallQueueData/Association ($($cq.Identity)): $_"
        }

        @{
            id                           = [string]$cq.Identity
            name                         = [string]$cq.Name
            languageId                   = [string]$cq.LanguageId
            routingMethod                = [string]$cq.RoutingMethod
            agentAlertTimeSeconds        = [int]$cq.AgentAlertTime
            allowOptOut                  = [bool]$cq.AllowOptOut
            conferenceMode               = [bool]$cq.ConferenceMode
            presenceBasedRouting         = [bool]$cq.PresenceBasedRouting
            useDefaultMusicOnHold        = [bool]$cq.UseDefaultMusicOnHold
            musicOnHoldAudioFileId       = if ($cq.MusicOnHoldAudioFileId)  { [string]$cq.MusicOnHoldAudioFileId  } else { $null }
            welcomeMusicAudioFileId      = if ($cq.WelcomeMusicAudioFileId) { [string]$cq.WelcomeMusicAudioFileId } else { $null }
            welcomeTtsPrompt             = [string]$cq.WelcomeTextToSpeechPrompt
            agentIds                     = $agentIds
            agentNames                   = $agentNames
            distributionListIds          = $distributionListIds
            distributionListNames        = $dlNames
            channelId                    = if ($cq.ChannelId)           { [string]$cq.ChannelId           } else { $null }
            channelUserObjectId          = if ($cq.ChannelUserObjectId) { [string]$cq.ChannelUserObjectId } else { $null }
            oboResourceAccountIds        = $oboRaIds
            oboResourceAccountNames      = $oboRaNames
            overflowThreshold            = $cq.OverflowThreshold
            overflowAction               = [string]$cq.OverflowAction
            overflowActionTargetId       = $overflowTargetId
            overflowActionTargetType     = $overflowTargetType
            overflowActionTargetName     = $overflowTargetName
            timeoutThresholdSeconds      = $cq.TimeoutThreshold
            timeoutAction                = [string]$cq.TimeoutAction
            timeoutActionTargetId        = $timeoutTargetId
            timeoutActionTargetType      = $timeoutTargetType
            timeoutActionTargetName      = $timeoutTargetName
            noAgentAction                = [string]$cq.NoAgentAction
            noAgentActionTargetId        = $noAgentTargetId
            noAgentActionTargetType      = $noAgentTargetType
            noAgentActionTargetName      = $noAgentTargetName
            serviceLevelThresholdSeconds = $cq.ServiceLevelThresholdResponseTimeInSecond
            associatedResourceAccounts   = $associatedRAs
        }
    })

    return $result
}