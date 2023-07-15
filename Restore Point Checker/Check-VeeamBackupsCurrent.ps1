<#
TITLE: Check-VeeamBackupsCurrent
PURPOSE: This script will check if the local and offsite Veeam backups are current based of the jobs scheduled options
CREATOR: Dan Meddock
CREATED: 17MAY2023
LAST UPDATED: 10JUL2023
#>

# Declarations

# Zero out $offsiteOutdatedCount variable
$eventSource = "Veeam Restore Point Checker"
$offsiteOutdatedCount = 0
$localOutdatedCount = 0
$outdatedJobs = @()

# Add the powershell snap in if applicable
Add-PSSnapin VeeamPSSnapin -erroraction silentlycontinue

# Function Definitions

# Function used to set the correct scheduling options used by the backup job.
## It will also set a time to compare and check if the backups are current.
function Get-BackupDateCheck ($scheduleOptions) {
    switch ($scheduleOptions) {
        {$_.OptionsDaily.Enabled}{
			$schedulingInfo = @{
				selectedSchedule = "Daily"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
		{$_.OptionsMonthly.Enabled}{
			$schedulingInfo = @{
				selectedSchedule = "Monthly"
				compareDate = ((Get-Date).AddDays(-30)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
		{$_.OptionsPeriodically.Enabled}{
			$schedulingInfo = @{
				selectedSchedule = "Periodically"
				compareDate = ((Get-Date).AddDays(-7)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
        {$_.OptionsContinuous.Enabled}{
			$schedulingInfo = @{
				selectedSchedule = "Continuously"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
        default{
            $schedulingInfo = @{
				selectedSchedule = "is Unknown"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
    }
}

# Main Logic

Try{
	# Check if EventLog exists; ; If not then create it
	if (![System.Diagnostics.EventLog]::SourceExists($eventSource)){New-Eventlog -LogName Application -Source $eventSource}
	
	# Pull job info for both local and offsite backups
	Write-Host "Getting backup job info...`n"
	
	# Get-VBRComputerBackupJob
	$localJobs = Get-VBRJob -WarningAction:SilentlyContinue | ? {$_.Info.IsScheduleEnabled -eq $true -and $_.typetostring -like "*Backup" -and (!($_.JobType -eq 'EpAgentBackup'))}
	$offsiteJobs = Get-VBRJob -WarningAction:SilentlyContinue | ? {$_.Info.IsScheduleEnabled -eq $true -and $_.typetostring -like "*Backup Copy" -and (!($_.JobType -eq 'EpAgentBackup'))}

	# Check local Veeam backups
	Write-Host "Checking local Veeam backups..."

	# Check the local backup jobs and get the time that backup job completed
	foreach ($localJob in $localJobs) {
		$jobName = $localJob.Name
		$lastBackup = (Get-VBRBackupSession | ? {($_.JobName -eq $jobName) -and ($_.IsCompleted -eq "True")} | Sort-Object CreationTime -Descending | Select-Object -First 1)
		$lastBackupTime = $lastBackup.endtime		
		$getSchedulingInfo = Get-BackupDateCheck $localJob.ScheduleOptions
		
		if ($lastBackupTime -eq $NULL){continue}

		if ($lastBackupTime -gt $getSchedulingInfo.compareDate) {
			[string]$currentMessage = "The latest local restore point for ""$jobName"" is current ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			Write-Host "$currentMessage"
			$eventLogOutput += @([string]$currentMessage)
		} else {
			[string]$outdatedMessage = "The latest local restore point for ""$jobName"" is outdated ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			Write-Host "$outdatedMessage"
			$eventLogOutput += @([string]$outdatedMessage)
			$localOutdatedCount++
			$outdatedJobs+=$jobName
		}
	}

	# Check offsite Veeam backups
	Write-Host "`nChecking offsite Veeam backups..."

	foreach ($offsiteJob in $offsiteJobs) {
		$jobName = $offsiteJob.Name
		$lastBackup = (Get-VBRBackupSession | Where-Object {($_.JobName -match $jobName) -and ($_.IsCompleted -eq "True")} | Sort-Object CreationTime -Descending | Select-Object -First 1)
		$lastBackupTime = $lastBackup.endtime		
		$getSchedulingInfo = Get-BackupDateCheck $offsiteJob.ScheduleOptions
		
		if ($lastBackupTime -eq $NULL){continue}
		
		if ($lastBackupTime -gt $getSchedulingInfo.compareDate) {
			[string]$currentMessage = "The latest offsite restore point for ""$jobName"" is current ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			Write-Host "$currentMessage"
			$eventLogOutput += @([string]$currentMessage)			
		} else {
			[string]$outdatedMessage = "The latest offsite restore point for ""$jobName"" is outdated ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			Write-Host "$outdatedMessage"
			$eventLogOutput += @([string]$outdatedMessage)
			$offsiteOutdatedCount++
			$outdatedJobs+=$jobName
		}
	}

	# Check backup status and exit with appropriate code
	if ($localOutdatedCount -eq 0 -and $offsiteOutdatedCount -eq 0) {
		Write-Host "`nAll backups are current."
		$eventType = "Information"
		# Event will contain all VM verification results
		Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 6907 -Message ($eventLogOutput | out-string)
		Exit 0
	} else {
		Write-Host "`nThe following backup jobs are outdated:"
		$eventType = "Error"
		# If any VM verifications fail it creates a failure event
		Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 6908 -Message ($eventLogOutput | out-string)
		Write-Host $outdatedJobs
		Exit 1
	}
}Catch{
	Write-Error "An error occurred: $($_.Exception.Message)"
}