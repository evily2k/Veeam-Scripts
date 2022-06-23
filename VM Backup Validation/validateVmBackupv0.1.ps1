# Veeam Backup Validator Report - Validate VM Last Backup

# This script validates all virtual machines last backup of the Veeam Backups Jobs. 
# It checks the backup files via CRC at the file level. 
# For the integrity validation of the backups the Validator uses the checksum algorithm.
# After each creation of a backup file, Veeam calculates a checksum for every data block in the backup file and will attach the checksums to them.
# The Veeam Backup Validator re-calculates the checksums for data blocks and compares them with the initial written values.

# Ideas:
# Possible integration into LT so you can pull up the MGT/VEEAM device view and see the results of the VM validation?
# Upload results in HTML to IT Glue maybe monthly like how in CW we have the last verified, this would be the same but with more details
# LT script to run maybe monthly and then results get uploaded to IT Glue

# $book = get-content .\AMC-DC1.xml
#[xml]$report = get-content $ReportName
# $book.Report.ResultInfo.Result
#$validatorResults = $report.Report.ResultInfo.Result

#	1 - Trace script lines as they run; 
#	2 - Trace script lines, variable assignments, function calls, and scripts.
# Enable debugging with desired trace settings; defaulted to 2

Set-PSDebug -Trace 2
# Import Veeams PowerShell snapin
Add-PSSnapin VeeamPSSnapin
# Get today's date
$todaysDate = (get-date).ToString("yyyyMMdd")
# Get date from one week ago
$lastWeek = (get-date).AddDays(-7).ToString("yyyyMMdd")
# Get date from one month ago
$lastMonth = (get-date).AddDays(-30)
# FLR testing report directory
$flrReport = "C:\ltworking\VeeamFLR\Report\Restore_Report.txt"
# Adds a header to the File Restore Report file
Add-Content -Path $flrReport "--------- File Restore Testing ($todaysDate) ---------"
# Clear VeeamFLR folders txt file contents
Remove-Item C:\ltworking\VeeamFLR\Restore\*.txt
# Name of the restore testing file
$fileName = "restoretesting.txt"
# Event log name
$eventName = "Veeam Validator Results"
# Keyword exclusion list
$excludeList = "C:\ltworking\VeeamFLR\Exclude\excludeList.txt"
# Pull names from exclusions list and store in array
$excludedNames = @(Get-Content -path C:\ltworking\VeeamFLR\Exclude\excludeList.txt)
#$excludedNames = @('VDI', 'USB', 'VCC', 'Quarterly', 'Historical', '8VM', 'MGT', 'XPVM', 'Point In Time', 'Not in Production', 'SmartLock', 'migrated', 'vMBG', 'TFBO', 'SBSSERVER', 'vCenter', 'Webserver', 'PointInTime')
# Uses RegEx to match exact characters in original string
$excludeRegex = [string]::Join('|', $excludedNames)

# Check if EventLog exists
If(![System.Diagnostics.EventLog]::SourceExists($eventName))
{
	# If not then create the Event log
	New-Eventlog -LogName Application -Source $eventName
}

# Get a list of all jobs in Veeam
foreach ($job in Get-VBRJob)
{	
	# If job test for "Backup" type, contains keywords, or is disabled is true then skip.
	If(($job.JobType -ne 'Backup') -or ($job.Name -match $excludeRegex) -or ($job.info.IsScheduleEnabled -ne $True)){continue}	
	# Get list of all backup jobs
	$vmRestore = Get-VBRJobObject -job $job.Name
	
	foreach ($vm in $vmRestore)
	{
		# Gets VM details from Host
		$findEnt = Find-VBRViEntity -name $vm.Name
		# If job contains keywords, Name is blank, or VM is powered off is true then skip.
		If(($vm.Name -match $excludeRegex) -or ($vm.Name -eq $NULL) -or ($findEnt.PowerState -eq 'PoweredOff') -or ($vm.ApproxSizeString -eq '0.0 B')){continue}
		# Set backup job name to string
		[string]$vmName = $vm.Name
		# Set backup job name to string
		[string]$backupName = $job.Name
		# Change directory Veeam Backup Validator directory
		set-location "C:\Program Files\Veeam\Backup and Replication\Backup"
		# Report name for vm validator results
		$ReportName="C:\ltworking\VeeamFLR\Report\$vmName-Backup-Validation-Report_$(get-date -f dd-MM-yyyy).xml"
		# Execute command to validate a vm's last backup
		&.\Veeam.Backup.Validator.exe /backup:$backupName /vmname:$vmName /report:$ReportName /format:xml
		
		# $book = get-content .\AMC-DC1.xml
		[xml]$report = get-content $ReportName
		# $book.Report.ResultInfo.Result
		$validatorResults = $report.Report.ResultInfo.Result
		If ($validatorResults -eq 'Success'){
			# Event type set to Information
			$eventType = "Information"
			# Success log entry
			$flrLog = "[$(Get-Date -format 'u')] [SUCCESS] [$vm.Name] Backup files successfully validated"
			# Write results to event log
			Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6904 -Message $flrLog
		}
		Else{
			# Event type set to Error
			$eventType = "Error"
			# Failure log entry
			$flrLog = "[$(Get-Date -format 'u')] [FAILURE] [$vm.Name] $volName - Backup file validation failed"
			# Write results to event log
			Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6905 -Message $flrLog
		}
	}
}