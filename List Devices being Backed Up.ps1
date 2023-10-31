<#
TITLE: Veeam - List Devices being Backed Up [WIN]
PURPOSE: Displays the devices that are being backed up in Veeam B&R
CREATOR: Dan Meddock
CREATED: 17OCT2023
LAST UPDATED: 31OCT2023
#>

# Declarations
$varString = "Veeam Backup & Replication"
$installCheck = ("HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") | % {gci -Path $_ | % {get-itemproperty $_.pspath} | ? {$_.DisplayName -eq "$varString"}}

# Main
Try{
    If ($installCheck -ne $NULL){
        # Import the Veeam PowerShell snap-in module
        Add-PSSnapin -Name VeeamPSSnapIn

        # Get all Veeam backup jobs
        $backupJobs = Get-VBRJob

        if ($backupJobs) {
			# Specify the path for the output CSV file
            $outputPath = "C:\temp\VMbackups.csv"

            # Create an array to store the backup job details
            $backupJobDetails = @()

            foreach ($job in $backupJobs) {
                # Get the list of VMs included in the backup job
                $backupVMs = Get-VBRJobObject -Job $job

                foreach ($vm in $backupVMs) {
                    $jobDetails = [PSCustomObject]@{
                        "Job Name" = $job.Name
                        "VM Name" = $vm.Name
                        # Add more properties as needed
                    }

                    $backupJobDetails += $jobDetails
                }
            }

            # Export the backup job details to a CSV file
            $backupJobDetails | Export-Csv -Path $outputPath -NoTypeInformation
            write-host "$backupJobDetails"

            Write-Host "Backup job details exported to: $outputPath"
        } else {
            Write-Host "No backup jobs found."
        }
		# Output results to stdout in DattoRMM
        type "C:\temp\vmBackups.csv"
        # Remove the Veeam PowerShell snap-in module
        Remove-PSSnapin -Name VeeamPSSnapIn
    }else{
        Write-Host "Veeam Backup and Replication is not installed on this device."
        Exit 1
    }
}catch{
		# Catch any errors thrown and exit with an error
		Write-Error $_.Exception.Message
}
Exit 0
