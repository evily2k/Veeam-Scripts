<#
TITLE: Veeam Backup Validator - Last VM Backup Report [WIN]
PURPOSE: This script validates all vm data from all local backup jobs and exports data to XML file and Success/Failure is logged to the event log for RMMM monitoring
	This script validates all virtual machines last backup of the Veeam Backups Jobs. 
	It checks the backup files via CRC at the file level. 
	For the integrity validation of the backups the Validator uses the checksum algorithm.
	After each creation of a backup file, Veeam calculates a checksum for every data block in the backup file and will attach the checksums to them.
	The Veeam Backup Validator re-calculates the checksums for data blocks and compares them with the initial written values.
CREATOR: Dan Meddock
CREATED: 20JUN2022
LAST UPDATED: 23JUN2022
#>

# Declarations
# Enable debugging with desired trace settings; defaulted to 2
#	1 - Trace script lines as they run; 
#	2 - Trace script lines, variable assignments, function calls, and scripts.
Set-PSDebug -Trace 2
# Import Veeams PowerShell snapin
Add-PSSnapin VeeamPSSnapin
# Event log name
$eventName = "Veeam Validator Results"
# Working directory
$reportDir = "C:\temp\VeeamFLR\Report"

# Main
# Check if EventLog exists
If(![System.Diagnostics.EventLog]::SourceExists($eventName))
{
	# If not then create the Event log
	New-Eventlog -LogName Application -Source $eventName
}

#Check if Report folder exists
If(!(test-path $reportDir -PathType Leaf)){new-item $reportDir -ItemType Directory -force}
	
# Get a list of all jobs in Veeam
foreach ($job in Get-VBRJob)
{	
	# If job test for "Backup" type or is disabled is true then skip.
	If(($job.JobType -ne 'Backup') -or ($job.info.IsScheduleEnabled -ne $True)){continue}	
	# Get list of all backup jobs
	$vmRestore = Get-VBRJobObject -job $job.Name
	
	foreach ($vm in $vmRestore)
	{
		# Gets VM details from Host
		$findEnt = Find-VBRViEntity -name $vm.Name
		# If job contains keywords, Name is blank, or VM is powered off is true then skip.
		If(($vm.Name -eq $NULL) -or ($findEnt.PowerState -eq 'PoweredOff') -or ($vm.ApproxSizeString -eq '0.0 B')){continue}
		# Set backup job name to string
		[string]$vmName = $vm.Name
		# Set backup job name to string
		[string]$backupName = $job.Name
		# Change directory Veeam Backup Validator directory
		set-location "C:\Program Files\Veeam\Backup and Replication\Backup"
		# Report name for vm validator results
		$ReportName="$($reportDir)\$vmName-Backup-Validation-Report_$(get-date -f dd-MM-yyyy).xml"
		# Execute command to validate a vm's last backup
		&.\Veeam.Backup.Validator.exe /backup:$backupName /vmname:$vmName /report:$ReportName /format:xml
		
		# Pull XML report file content into variable
		[xml]$report = get-content $ReportName
		# Get Validator result info
		$validatorResults = $report.Report.ResultInfo.Result
		# Check for "Succes" in XML report and create event log entry
		If ($validatorResults -eq 'Success'){
			# Event type set to Information
			$eventType = "Information"
			# Success log entry
			$flrLog = "[$(Get-Date -format 'u')] [SUCCESS] [$vm.Name] Backup files successfully validated"
			# Write results to event log
			Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6904 -Message $flrLog
			Write-host $flrlog
		}
		# Create event log entry for validation failure
		Else{
			# Event type set to Error
			$eventType = "Error"
			# Failure log entry
			$flrLog = "[$(Get-Date -format 'u')] [FAILURE] [$vm.Name] $volName - Backup file validation failed"
			# Write results to event log
			Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6905 -Message $flrLog
			Write-host $flrlog
		}
	}
}
