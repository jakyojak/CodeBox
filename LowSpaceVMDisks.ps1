#Script to create tickets on ticketing system for VMs with low space disks.
#Uses a cache file to prevent duplicate notifications being sent and self manages removal of items in cache file for disks that are no longer low on space.
#Ran daily via a scheduled task

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
Set-Location "\\servernameredacted.campus.bath.ac.uk\reports$"

#The amount of free disk space left on VM disks that we want to report on
[single]$ThreshHoldPerecent = 5

[bool]$IgnoreBDrives=$true
[psobject]$list=@()
[psobject]$vm=@()
[psobject]$VMs=@()
[psobject]$SentEmailcsv=@()
[string]$outdir = "Path Redacted"
[string]$SentEmailpath="$($outdir)LowSpaceDisks-AlreadySent-DoNotDelete.csv"
[string]$ReportFile = "$($outdir)LowSpaceDisks-" + $(Get-Date -Format yyyy-MM-dd) + ".csv"
[string]$SMTPServer= "mail.bath.ac.uk"
[string]$FromAddress="no reply <no-reply@bath.ac.uk>"
[string]$body=" has a number of disks that are under ${ThreshHoldPerecent}% capacity."
[string]$scriptErrorBody="This is an automated message.

The automated task Send-Low-Disk-Space-Emails on Endeavor has failed to connect to both vCenters successfully

The error is logged in \\servernameredacted.campus.bath.ac.uk\reports$\LowSpaceDisks\LowDiskSpaceEmailsLog.txt

Thanks,

Servers and Storage Team"

#Import the list of contacts and vCenter folders
[hashtable]$Contact=Get-Content -raw "C:\scripts\Components\Contacts.txt" | ConvertFrom-StringData

#credentials
$UserName = "User Redacted"
$pass = Get-Content "Path Redacted" | ConvertTo-SecureString
$creds=[pscredential]::new($UserName,$pass)

#Connect to both vcenters for reading the folders and the vms contained within them. Credentials are used from the scheduled task to connect.
$VCSession1=Connect-VIServer -Server "Address redacted"
$VCSession2=Connect-VIServer -Server "Address redacted"

if     (($VCSession1 -eq $null) `
   -or ($VCSession2 -eq $null)) {
   Send-MailMessage -From $FromAddress `
                    -To "it-server-storage@bath.ac.uk" `
                    -Subject "Low Space Disks script error" `
                    -SmtpServer $SMTPServer `
                    -Body  $scriptErrorBody;exit}

#get all folders in vcenter1 and 2 and then all VMs inside each department folder that match the contacts list              
foreach ($folder in ($Contact.Keys| Sort-Object)) {$VMs=get-folder -Name $folder | Get-VM

                                     foreach ($vm in $VMs) {
                                                            $details= New-Object System.Object
                                                            $details | Add-Member -MemberType NoteProperty -Name Folder -Value $folder
                                                            $details | Add-Member -MemberType NoteProperty -Name VMname -Value $VM.name
                                                            $details | Add-Member -MemberType NoteProperty -Name EMail -Value $contact[$folder]
                                                            $list+=$details
                                                            $details=$null
                                                            }
                                                    }

#Also get Corporate App's VMs (Not all VMs are stored within folders)
Get-Datacenter |? {$_.Name -match ".*SQL-4ES.*|.*SQL-5W.*"} | Get-VM | Sort-Object | % {
                                                                                        $details= New-Object System.Object
                                                                                        $details | Add-Member -MemberType NoteProperty -Name Folder -Value "Corporate Applications and Databases"
                                                                                        $details | Add-Member -MemberType NoteProperty -Name VMname -Value $_.name
                                                                                        $details | Add-Member -MemberType NoteProperty -Name EMail -Value "it-applications-databases@bath.ac.uk"
                                                                                        If ($_.name -match ".*exchvm01.*|.*exchvm02.*") {
                                                                                             $details= New-Object System.Object
                                                                                             $details | Add-Member -MemberType NoteProperty -Name Folder -Value "Communications & Collaboration"
                                                                                             $details | Add-Member -MemberType NoteProperty -Name VMname -Value $_.name
                                                                                             $details | Add-Member -MemberType NoteProperty -Name EMail -Value "it-comms-collaboration@bath.ac.uk"
                                                                                                                                          }
                                                                                        $list+=$details
                                                                                        $details=$null
                   }

#Remove old disk space report
gci -Path "${outdir}" -Recurse |? {$_.name -like "LowSpaceDisks-20??*"} | Remove-Item -force

#Generate new lowdiskspace report
$CSV=@()
$FullVM = Get-View -ViewType VirtualMachine | Where-Object {-not $_.Config.Template}
$AllVMs = $FullVM | Where-Object {-not $_.Config.Template `
                                  -and $_.Runtime.PowerState `
                                  -eq "poweredOn" `
                                  -And (    $_.Guest.toolsStatus `
                                        -ne "toolsNotInstalled" `
                                        -And $_.Guest.ToolsStatus `
                                        -ne "toolsNotRunning")} `
                                  | Select-Object *, @{N="NumDisks";E={@($_.Guest.Disk.Length)}} `
                                  | Sort-Object -Descending NumDisks
ForEach ($VMdsk in $AllVMs){
   Foreach ($disk in $VMdsk.Guest.Disk){
      if ((($disk.FreeSpace/$disk.Capacity) -lt ($ThreshHoldPerecent/100))){
         $CSV+=New-Object -TypeName PSObject -Property ([ordered]@{
            "vm"            = $VMdsk.name
            "Path"            = $Disk.DiskPath
            "Capacity"   = ([math]::Round($disk.Capacity/ 1MB))
            "FreeSpace" =([math]::Round($disk.FreeSpace / 1MB))
            "PercentFree" =[math]::Round(($disk.FreeSpace/$disk.Capacity)*100,2)
         })
      }
   }
}

#Create the report file
$CSV | sort-object -Property vm | Export-Csv -Path $ReportFile -NoTypeInformation

#Import the VM disks that have already had emails sent out for them and..
$Alreadysentemails=Import-Csv -Path "Path Redacted"

#..compare that list with new disks
$CompareList=Compare-Object -ReferenceObject @($CSV| Select-Object) -IncludeEqual -DifferenceObject @($Alreadysentemails| Select-Object) -Property VM, path
$CompareList = $CompareList | Group-Object VM | Select-Object name,count -ExpandProperty Group -EA SilentlyContinue

#Send one e-mail for each vm that has new disk that is below the threshold
write-host("Sending E-mails to: `n")
ForEach ($VM in ($CompareList |? {$_.SideIndicator -eq "<="} | select VM -unique)) {
                                                     $HardDisks=@()

                                                      #+ $("`t"|Out-String) will insert a tab, this will stop outlook removing the line breaks.
                                                      # This only becomes a problem if the recipient is viewing the e-mail in a client such as outlook.
                                                     $CSV |? {$_.vm -match $VM.vm} `
                                                          |% {$Harddisks+=$_.path + " has " + $_.FreeSpace + "MB (" + $_.PercentFree + "%) remaining " + $("`t"|Out-String)}

                                                     #Work out what e-mails need to be sent
                                                     $vmemail=($list |? {$_.vmname -eq $VM.vm}).EMail


                                                     #Don't send an e-mail if the B:\ drive is the only drive that is low on space on the VM. VM and drive will still get added to the cache file for monitoring purposes even if an e-mail is not sent
                                                     if ((($IgnoreBDrives -eq $true) `
                                                            -and ($CompareList |? {$_.vm -eq $vm.vm}).count -eq "1") `
                                                            -and (($CompareList |? {$_.vm -eq $vm.vm}).path -contains "B:\")) {
                                                                write-host ("Script has not sent an e-mail for the B:\ drive of " + $vm.vm + "`n")
                                                     }

                                                     Else {
                                                     write-host($vmemail)
                                                     write-host($VM.vm)
                                                     write-host($HardDisks)
                                                     Send-MailMessage -From $FromAddress -To $vmemail -Subject ("VMware VM Low Disk Space Notification - " + $vm.vm) -SmtpServer $SMTPServer -Body ("FAO: $($vmemail)`n`nThe VMware VM " + $VM.vm + $body + "`n`n" + $Harddisks + "`nThanks,`nServers and Storage Team")
                                                     }
                                                     }
                                                     

#Cache all of the disks that are new or still present from the last time the script was run (disk space is omitted as that could change between reports)
$RemoveVms=New-Object System.Object
$RemoveVms=$CompareList | Sort-Object -Property vm |? {($_.SideIndicator -eq "=>")} | select vm,path
write-output "Removing the following VM disks from the cache file:" $RemoveVms
write-output "`n"

$outvms=New-Object System.Object
$outvms= $CompareList | Sort-Object -Property vm |? {($_.SideIndicator -eq "<=") -or ($_.SideIndicator -eq "==")} | select vm,path
write-output "Updating the cache file with present and new vm disks:" $outvms

#Write out the report CSV for the next time the script runs
$outvms | Export-Csv -Path "Path Redacted" -NoTypeInformation
