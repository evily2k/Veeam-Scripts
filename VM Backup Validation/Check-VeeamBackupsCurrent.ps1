<#
TITLE: Check-VeeamBackupsCurrent
PURPOSE: This script will check if the Veeam backups are current based of their schedule options
CREATOR: Dan Meddock
CREATED: 17MAY2023
LAST UPDATED: 18MAY2023
#>

# Declarations

# Zero out $offsiteOutdatedCount variable
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
        {$_.OptionsDaily.Enabled} {
			$schedulingInfo = @{
				selectedSchedule = "Daily"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
		{$_.OptionsMonthly.Enabled} {
			$schedulingInfo = @{
				selectedSchedule = "Monthly"
				compareDate = ((Get-Date).AddDays(-30)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
		{$_.OptionsPeriodically.Enabled} {
			$schedulingInfo = @{
				selectedSchedule = "Periodically"
				compareDate = ((Get-Date).AddDays(-7)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
        {$_.OptionsContinuous.Enabled} {
			$schedulingInfo = @{
				selectedSchedule = "Continuous"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
        default {
            $schedulingInfo = @{
				selectedSchedule = "Unknown"
				compareDate = ((Get-Date).AddDays(-1)).ToString("yyyy-M-dd")
			}
			return $schedulingInfo
        }
    }
}

# Main Logic

Try{
	# Pull job info for both local and offsite backups
	Write-Host "Getting backup job info."
	$localJobs = Get-VBRJob | ? {$_.Info.IsScheduleEnabled -eq $true -and $_.typetostring -like "*Backup"}
	$offsiteJobs = Get-VBRJob | ? {$_.Info.IsScheduleEnabled -eq $true -and $_.typetostring -like "*Backup Copy"}

	# Check local Veeam backups
	Write-Host "Checking local Veeam backups..."

	# Check the local backup jobs and get the time that backup job completed
	foreach ($localJob in $localJobs) {
		$jobName = $localJob.Name
		$lastBackup = (Get-VBRBackupSession | ? {($_.JobName -eq $jobName) -and ($_.IsCompleted -eq "True")} | Sort-Object CreationTime -Descending | Select-Object -First 1)
		$lastBackupTime = $lastBackup.endtime
		
		$getSchedulingInfo = Get-BackupDateCheck $localJob.ScheduleOptions

		if ($lastBackupTime -gt $getSchedulingInfo.compareDate) {
			Write-Host "The latest local restore point for ""$jobName"" is current ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
		} else {
			Write-Host "The latest local restore point for ""$jobName"" is outdated ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			$localOutdatedCount++
			$outdatedJobs+=$jobName
		}
	}

	# Check offsite Veeam backups
	Write-Host "Checking offsite Veeam backups..."

	foreach ($offsiteJob in $offsiteJobs) {
		$jobName = $offsiteJob.Name
		$lastBackup = (Get-VBRBackupSession | Where-Object {($_.JobName -match $jobName) -and ($_.IsCompleted -eq "True")} | Sort-Object CreationTime -Descending | Select-Object -First 1)
		$lastBackupTime = $lastBackup.endtime
		
		if ($lastBackupTime -gt $getSchedulingInfo.compareDate) {
			Write-Host "The latest offsite restore point for ""$jobName"" is current ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."			
		} else {
			Write-Host "The latest offsite restore point for ""$jobName"" is outdated ($lastBackupTime) and scheduled to run $($getSchedulingInfo.selectedSchedule)."
			$offsiteOutdatedCount++
			$outdatedJobs+=$jobName
		}
	}

	# Check backup status and exit with appropriate code
	if ($localOutdatedCount -eq 0 -and $offsiteOutdatedCount -eq 0) {
		Write-Host "All backups are current."
		Exit 0
	} else {
		Write-Host "The following backup jobs are outdated."
		Write-Host $outdatedJobs
		Exit 1
	}
}Catch{
	Write-Error "An error occurred: $($_.Exception.Message)"
}