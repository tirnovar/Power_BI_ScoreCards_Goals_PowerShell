$ErrorActionPreference = "Stop"

$publicEndpoint = "https://api.powerbi.com"

if (!(Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt)) {
    try {
        Install-Module -Name MicrosoftPowerBIMgmt -AllowClobber -Confirm:$False -Force  
    }
    catch [Exception] {
        $_.message 
        exit
    }
}

Login-PowerBI

$token = (Get-PowerBIAccessToken)["Authorization"]

function GetApiUrl() {
    $response = Invoke-WebRequest -Uri "$publicEndpoint/metadata/cluster" -Headers @{ "Authorization"=$token }
    $cluster = $response.Content | ConvertFrom-Json
    return $cluster.backendUrl
}

$api = GetApiUrl

function GetScorecard($scorecardId) {
    Write-Host "Retrieving scorecard..." -NoNewLine
    $response = Invoke-WebRequest `
        -Uri "$api/v1.0/myOrg/internalScorecards($scorecardId)?`$expand=goals" `
        -Headers @{ "Authorization"=$token }
    Write-Host -ForegroundColor Green OK
    $scorecard = $response.Content | ConvertFrom-Json
    return $scorecard
}

function GetGoal($scorecardId, $goalId) {
    Write-Host "Retrieving scorecard..." -NoNewLine
    $response = Invoke-WebRequest `
        -Uri "$api/v1.0/myOrg/internalScorecards($scorecardId)/goals($goalId)" `
        -Headers @{ "Authorization"=$token }
    Write-Host -ForegroundColor Green OK
    $goal = $response.Content | ConvertFrom-Json
    return $goal
}

function CopyGoal($sourceGoal, $destinationScorecardId, $parentGoalId, $destinationWsId) {
    Write-Host "Copying ""$($sourceGoal.name)""... " -NoNewline
    try {
        $newGoalRequest = $sourceGoal | select -Property name, startDate, completionDate, unit, owner, additionalOwners, valuesFormatString, datesFormatString
        $newGoalRequest.name = "PLACEHOLDER"
        $response = Invoke-WebRequest `
            -Method Post `
            -Uri "$api/v1.0/myOrg/groups/$destinationWsId/internalScorecards($destinationScorecardId)/goals" `
            -Headers @{ "Authorization"=$token } `
            -Body ($newGoalRequest | ConvertTo-Json) `
             -ContentType "application/json"
        
        $goal = $response.Content | ConvertFrom-Json

        Write-Host -ForegroundColor Green OK

        if ($sourceGoal.statusRules) {
            CopyStatusRules -goal $sourceGoal -destinationScorecardId $destinationScorecardId -destinationGoalId $goal.id
        }

        return $goal
    } catch {
        Write-host -ForegroundColor Red "Could not copy goal"
        throw
    }
}

function CopyStatusRules($goal, $destinationScorecardId, $destinationGoalId) {
    Write-Host " - Copying status rules... " -NoNewline
    $response = Invoke-WebRequest `
               -Uri "$api/v1.0/myOrg/internalScorecards($($goal.scorecardId))/goals($($goal.id))/statusRules" `
               -Headers @{ "Authorization"=$token }
    $rules = $response.Content | ConvertFrom-Json 
    $response = Invoke-WebRequest `
               -Method Post `
               -Uri "$api/v1.0/myOrg/internalScorecards($destinationScorecardId)/goals($destinationGoalId)/statusRules" `
               -Body ($rules | ConvertTo-Json -Depth 100) `
               -ContentType "application/json" `
               -Headers @{ "Authorization"=$token }
    Write-Host -ForegroundColor Green OK
}

function DuplicateGoal($idScorecard, $sourceScorecard, $duplicates, $sourceGoal, $destinationWSId) {
    $goalsByParentId = @{}
    $topLevelGoals = @()
        if ($sourceGoal.parentId) {
            if (!$goalsByParentId[$sourceGoal.parentId]) {
                $goalsByParentId[$sourceGoal.parentId] = @()
            }
            $goalsByParentId[$sourceGoal.parentId] += $sourceGoal
        } else {
            $topLevelGoals += $sourceGoal
        }

    Write-Host "Duplicating $($originGoalId.goals.Length+1) goal to scorecard $sourceScorecard..."

    for (($refreshes = 0); $refreshes -lt $duplicates; $refreshes++) {
        CopyGoal -sourceGoal $sourceGoal -destinationScorecardId $idScorecard -parentGoalId $goalsByParentId -destinationWsId $destinationWSId
        Write-Host "Count of done duplicates: $($refreshes+1) "
    }
    Write-Host "Done"
}

function ShowPrompt() {
    while ($true) {
        Write-Host -ForegroundColor Yellow "Scorecard cloning utility"
        Write-Host "Choose action:"
        Write-Host " [c] - Copy goals to an target scorecard"
        Write-Host " [q] - Quit"

        $action = Read-Host -Prompt "Choose action or press enter to duplicate a scorecard"

        break
    }

    if ($action -and  ($action -ne "c")) {
        if ($action -ne "q") {
            Write-Host -ForegroundColor red "Invalid action"
            return $false
        }
    }

    $scorecardId = Read-Host -Prompt "Enter source scorecard id"
    if (!$scorecardId) {
        Write-Error "Invalid scorecard id"
    }

    $sourceScorecard = GetScorecard -scorecardId $scorecardId
    Write-Host -ForegroundColor Green "Scorecard: $($sourceScorecard.name). Workspace: $($sourceScorecard.groupId)"

    $targetScorecardId = Read-Host -Prompt "Enter target scorecard id"
    if (!$targetScorecardId) {
        Write-Error "Invalid target scorecard id"
    } if ($targetScorecardId -ne $sourceScorecard) {
        Write-Host -ForegroundColor red "Target scorecard id must differend the same as source scorecard id"
    }

    $targetScorecard = GetScorecard -scorecardId $scorecardId
    Write-Host -ForegroundColor Green "Scorecard: $($targetScorecard.name). Workspace: $($targetScorecard.groupId)"
    $destinationWorkspaceId = $targetScorecard.groupId

    $goalId = Read-Host -Prompt "Enter source goal id"
    if (!$scorecardId) {
        Write-Error "Invalid scorecard id"
    }

    $sourceGoal = GetGoal -scorecardId $scorecardId -goalId $goalId
    Write-Host -ForegroundColor Green "Goal: $($sourceGoal.name)"

    $numberOfDuplicates = Read-Host -Prompt "Enter number of duplicates to create"
    if (!$numberOfDuplicates) {
        Write-Error "Invalid number of duplicates"
    }
    if ($action -eq "c") {
               DuplicateGoal -idScorecard $scorecardId -sourceScorecard $sourceScorecard -duplicates $numberOfDuplicates -sourceGoal $sourceGoal -destinationWSId $destinationWorkspaceId
    }
}

ShowPrompt