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
Version: 0.6
#>

Set-PSDebug -Trace 2

# Declarations
Add-PSSnapin VeeamPSSnapin
$eventName = "Veeam Validator Results"
$todaysDate = (get-date).ToString("yyyyMMdd")
$reportDir = "C:\temp\VeeamFLR\Report"
$VBVReportName = "Veeam Validator Results.txt"
$VBVReport = "$($reportDir)\$($VBVReportName)"
$VBVReportHeader = "--------- Veeam Validator Results ($todaysDate) ---------"

# Main
# Check if EventLog exists; ; If not then create it
if (![System.Diagnostics.EventLog]::SourceExists($eventName)){New-Eventlog -LogName Application -Source $eventName}

#Check if Report folder exists; If not then create it
if (!(test-path $reportDir -PathType Leaf)){new-item $reportDir -ItemType Directory -force}

# Check if logfile exists; If not then create it
if (!(Test-Path $VBVReport)){
	New-Item -path $reportDir -name $VBVReportName -type "file" -value $VBVReportHeader
	Add-Content -Path $VBVReport "`n"
}else{
	Add-Content -Path $VBVReport "`r`n", $VBVReportHeader
}

# Get all local Veeam backup jobs
foreach ($job in Get-VBRJob){
	
	# Skip jobs that aren't backup type or not scheduled
	if (($job.JobType -ne 'Backup') -or ($job.info.IsScheduleEnabled -ne $True)){continue}
	
	# Get all VMs listed in backup job
	$vmRestore = Get-VBRJobObject -job $job.Name
	
	foreach ($vm in $vmRestore){
		
		# Verify VM has a name, is powered on, and size is greater than zero
		$findEnt = Find-VBRViEntity -name $vm.Name
		if (($vm.Name -eq $NULL) -or ($findEnt.PowerState -eq 'PoweredOff') -or ($vm.ApproxSizeString -eq '0.0 B')){continue}
		
		# Set VM and Backup names to variables
		[string]$vmName = $vm.Name
		[string]$backupName = $job.Name
		# Veeam Validator report 
		$ReportName="$($reportDir)\$vmName-Backup-Validation-Report_$(get-date -f dd-MM-yyyy).xml"		
		
		# Change working directory to the Veeam Validator program directory
		set-location "C:\Program Files\Veeam\Backup and Replication\Backup"
		# Start the Veeam Validation process and export the report as XML (can be XML or HTML)
		&.\Veeam.Backup.Validator.exe /backup:$backupName /vmname:$vmName /report:$ReportName /format:xml
		
		# Get XML report content and verify success or failure
		[xml]$report = get-content $ReportName
		$validatorResults = $report.Report.ResultInfo.Result
		if ($validatorResults -eq 'Success'){
			[string]$VBVlog = "[$(Get-Date -format 'u')] [SUCCESS] [$vmName] VM backup file verification completed successfully."
			Write-host $VBVlog
			$VBVresults += @($VBVlog)
			Add-Content -Path $VBVReport -Value $VBVlog
		}else{
			[string]$VBVlog = "[$(Get-Date -format 'u')] [FAILURE] [$vmName] VM backup file verification failed. Need to review backup health."
			Write-host $VBVlog
			$VBVresults += @([string]$VBVlog)
			Add-Content -Path $VBVReport -Value $VBVlog
			$VBVErrors = $true
		}
		
	}
}
# Output all results to the event log as one event
if (!($VBVErrors)){
	$eventType = "Information"
	# Event will contain all VM verification results
	Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6904 -Message ($VBVresults | out-string)
}else{
	$eventType = "Error"
	# If any VM verifications fail it creates a failure event
	Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId 6905 -Message ($VBVresults | out-string)
}