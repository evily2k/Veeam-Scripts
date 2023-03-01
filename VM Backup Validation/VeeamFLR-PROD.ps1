Set-PSDebug -Trace 2
Add-PSSnapin VeeamPSSnapin
$todaysDate = (get-date).ToString("yyyyMMdd")
$lastWeek = (get-date).AddDays(-7).ToString("yyyyMMdd")
$lastMonth = (get-date).AddDays(-30)
$flrReport = "C:\ltworking\VeeamFLR\Report\Restore_Report.txt"
Add-Content -Path $flrReport "--------- File Restore Testing ($todaysDate) ---------"
Remove-Item C:\ltworking\VeeamFLR\Restore\*.txt
$fileName = "restoretesting.txt"
$eventName = "File Restore Testing"
$excludeList = "C:\ltworking\VeeamFLR\Exclude\excludeList.txt"
$excludedNames = @(Get-Content -path C:\ltworking\VeeamFLR\Exclude\excludeList.txt)
$excludeRegex = [string]::Join('|', $excludedNames)
$maxRepeat = 10
$checkInclude = "C:\ltworking\VeeamFLR\Exclude\includeList.txt"
$lockedRP = "is locked by running session"

# FLR testing event log results
Function GetEventType {
	param([switch] $good, [switch] $outOfDate, [switch] $missingFile, [switch] $missingLTagent, [switch] $errorFLR, [switch] $FLRtoStart,
	[Parameter (Mandatory=$true)] [int32] $eventID)	

	If($good)
	{	
		$eventType = "Information"
		$flrLog = "[$(Get-Date -format 'u')] [SUCCESS] [$($vm.Name)] $volName - File is current and restored successfully ($fileDate)"
	}
	If($outOfDate)
	{	
		$eventType = "Warning"
		$flrLog = "[$(Get-Date -format 'u')] [WARNING] [$($vm.Name)] $volName - File is out of date ($fileDate)"
	}
	If($missingFile)
	{	
		$eventType = "Error"
		$flrLog = "[$(Get-Date -format 'u')] [FAILED] [$($vm.Name)] $volName - File is missing; Investigate why."
	}
	If($missingLTagent)
	{	
		$eventType = "Error"
		$flrLog = "[$(Get-Date -format 'u')] [ERROR] [$($vm.Name)] Doesn't have a LT agent installed. Added to Exclusions list."
		#$vmExclude = $vm.name
		#Add-Content -Path $excludeList -Value $vmExclude
	}
	If($errorFLR)
	{	
		$global:errorJob = @($job)
		$eventType = "Error"
		$flrLog = "[$(Get-Date -format 'u')] [ERROR] [$($vm.Name)] Error occurred during restore testing; check validation report."
	}
	If($FLRtoStart)
	{	
		$global:errorJob = @($job)
		$eventType = "Error"		
		If($Error -match $lockedRP){$flrError = "FLR failed because restore point is locked by a running job"
			$flrLog = "[$(Get-Date -format 'u')] [ERROR] [$($vm.Name)] $flrError."
		}Else{
			$flrLog = "[$(Get-Date -format 'u')] [ERROR] [$($vm.Name)] FLR Failed. $Error"
			New-Item -Path "C:\ltworking\VeeamFLR\Restore" -name "$($vm.Name)_Error_Log.txt" -ItemType "file" -Value "$Error"
		}
	}
	Write-EventLog -LogName Application -Source $eventName -EntryType $eventType -EventId $eventID -Message $flrLog
	Add-Content -Path $flrReport -Value $flrLog
	$Error.clear()
}

If(![System.Diagnostics.EventLog]::SourceExists($eventName)){New-Eventlog -LogName Application -Source $eventName}

do 
{
	$jobsworking = @(Get-VBRJob| Where {$_.GetLastState() -eq "Working" -and $_.IsBackupJob -eq "True"})
	$maxRepeat--
	If($jobsworking.Count -ne 0){sleep -Seconds 300}
} until ($jobsworking.Count -eq 0 -or $maxRepeat -eq 0)

$jobsLocal = @(Get-VBRJob| Where {$_.JobType -eq "Backup"})

foreach ($job in $jobsLocal)
{	
	If($job.Name -match $excludeRegex){continue}
	If(!($job.info.IsScheduleEnabled)){continue}
	If($job.JobType -eq "BackupSync"){continue}
	
	$vmRestore = Get-VBRJobObject -job $job.name
	
	foreach ($vm in $vmRestore)
	{
		$findEnt = Find-VBRViEntity -name $vm.Name
		If(($vm.Name -match $excludeRegex) -or ($vm.Name -eq $NULL) -or ($findEnt.PowerState -eq 'PoweredOff')){continue}
		Try{$WFLR = Get-VBRRestorePoint -Name $vm.name -Backup $job.name | Sort CreationTime -Descending | Select -First 1 | Start-VBRWindowsFileRestore -ErrorAction SilentlyContinue}
		Catch{GetEventType -FLRtoStart -eventID 6906}
		$volumeArray = $WFLR.drives -split ', '
		$LTinstalled = $Null
		Foreach ($mountPath in $volumeArray)
		{
			$agentRecent = test-path "$mountPath\Windows\LTSvc\LTSVCMon.txt" -NewerThan $lastMonth
			If ($agentRecent){$LTinstalled = $True}
		}
		If (!($LTinstalled)){GetEventType -missingLTagent -eventID 6904}
		Else
		{
			Foreach ($mountPath in $volumeArray) 
			{     
				$sysVolCheck = test-path "$mountPath\BOOTSECT.BAK" -PathType Leaf
				$efiCheck = test-path "$mountPath\EFI" -PathType Container
				$mountCheck = Get-ChildItem $mountPath | Measure-Object
				If(($sysVolCheck) -or ($efiCheck) -or ($mountCheck.count -eq 0)){continue}
				
				$getNames = $mountPath.split("\\") 	
				$volName = $getNames[3]
				$restorePath = join-path -path $mountPath $fileName	
				$fileCheck = Test-Path -LiteralPath $restorePath

				If($fileCheck) 
				{
					$fileDate = Get-Content -Path $restorePath -TotalCount 1
					If($fileDate -gt $lastWeek){GetEventType -good -eventID 6901}Else{GetEventType -outOfDate -eventID 6902}	
				}
				Else 
				{
					$directory = Get-Item $mountPath
					$winVolume = test-path "$directory\Windows" -PathType Container
					If ($winVolume){GetEventType -missingFile -eventID 6903}
					Else
					{
						[Long]$actualSize = 0
						foreach ($item in (Get-ChildItem $mountPath -recurse | Where {-not $_.PSIsContainer} | ForEach-Object {$_.FullName})) 
						{
							$actualSize += (Get-Item $item).length
							If ($actualSize -gt 1GB){break}
						}
						If ($actualSize -lt 1GB){continue}
						Else{GetEventType -errorFLR -eventID 6905}
					}
				}
			} 
		}
		Stop-VBRWindowsFileRestore $WFLR
	}
}