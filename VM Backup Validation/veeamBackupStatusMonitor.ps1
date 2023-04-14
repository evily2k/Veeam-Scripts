Add-PSSnapin VeeamPSSnapin
        $VbrJobs = Get-VBRJob | Sort-Object typetostring, name
        
        Foreach($Job in $VbrJobs)
        {
            $JobName = $Job.Name
            $Result = $Job.GetLastResult()
        }


$jobs = get-vbrjob | where-object {$_.info.IsScheduleEnabled -eq $True} | Sort-Object typetostring, name

foreach ($job in $Jobs){
	if($job.ScheduleOptions.OptionsDaily.Enabled){
		$backupDateCheck = ((Get-Date).AddDays(-1)).tostring("yyyy-M-dd")
	}elseif($job.ScheduleOptions.OptionsMonthly.Enabled){
		$backupDateCheck = ((Get-Date).AddDays(-30)).tostring("yyyy-M-dd")
	}else{
		$backupDateCheck = ((Get-Date).AddDays(-1)).tostring("yyyy-M-dd")
	}

	$lastBackup = (Get-VBRBackupSession | Where {$_.JobName -eq $job.name} | Sort Creationtime -Descending | Select -First 1).endtime
	
	if ($lastbackup -gt $backupDateCheck){
		write-host "$job.name is current"
		
	}else{
		write-host "$Job.name is outdated"
	}
}
