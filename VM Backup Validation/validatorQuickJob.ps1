The following VMs are corrupted Unable to read metadata

# Change working directory to the Veeam Validator program directory
		set-location "C:\Program Files\Veeam\Backup and Replication\Backup"
		
# Start the Veeam Validation process and export the report as XML (can be XML or HTML)
&.\Veeam.Backup.Validator.exe /backup:"local backup only" /vmname:"PBX_replica" /report:"C:\temp\PBX_replica_$(get-date -f dd-MM-yyyy).html" /format:hmtl
		
Add-PSSnapin VeeamPSSnapin
$job = Get-VBRJob
$vmName = $job[6].name
set-location "C:\Program Files\Veeam\Backup and Replication\Backup"
&.\Veeam.Backup.Validator.exe /backup:"SSTSERVER" /vmname:$vmname /report:"C:\KEworking\VeeamFLR\Report\$vmName-Backup-Validation-Report_$(get-date -f dd-MM-yyyy).html" /format:html