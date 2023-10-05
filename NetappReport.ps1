#Connects to the Netapp and produces a report of each user's research storage area
#Also outputs storage areas with low disk space as an alert in CheckMK monitoring

$CSV= "C:\Program Files (x86)\check_mk\temp\quotareport.csv"
$date=(get-date)

function readreport {
$CSV= "C:\Program Files (x86)\check_mk\temp\quotareport.csv"
[int]$Threshhold=95
try { $report = Import-Csv $CSV}
    catch {throw "Error reading quotareport.csv"}
If ($report) {
              $result=$report| select * |? {[double]$_.percentageused -gt $Threshhold}
              $i=0
              $result|% { {
                         If ([double]$_.percentageused -lt [int]98){
                                                                   $Status=1 #warn
                                                                   }
                         Elseif ([double]$_.percentageused -ge [int]98){
                                                                        $Status=2 #crit
                                                                       }
             
                          $msg= $_.SVM + "/" + $_.Volume + "/" + $_.User + " is " + $_.percentageused + "% used (" + $_.used + "/" + $_.limit + ") " + (([int]$_.limit.replace("GB",""))-([int]$_.used.replace("GB",""))) + "GB free"
                          Write-output "$status Qtree_check_$i count=-; $msg"
                          $i++
                          }
              }}
}

function getnetappreport {

$items=@()
$keyfile = Redacted
$UserName = Redacted
$pass = "anything" | ConvertTo-SecureString -AsPlainText -force #Not actually anything. Uses an SSH key pair to connect instead, but needs a credential object to connect the SSH session.
$SVM="servername redacted"

$creds=[pscredential]::new($UserName,$pass)
#write-host "connecting to netapp"
try {$ssh= New-SSHSession -ComputerName $SVM -KeyFile $keyfile -Credential $creds -AcceptKey}
     catch { throw "Error connecting to $SVM via ssh"}

    If ($ssh) { #write-host "running ssh command"
                $out =(Invoke-SSHCommand -SSHSession $ssh -Command "set -showseparator '!';set -rows 0;set -units GB;volume quota report -fields volume,tree,disk-used,disk-limit").output.replace("'","")
                $ssh.Disconnect()
                Get-SSHSession |% {Remove-SSHSession $_.sessionid} | Out-Null
                $Qtrees = New-Object 'PsObject[]'($out.length)

                $i=0
                foreach ($qtree in $out){
                                if ($qtree.startswith("vresearch2")){
                                                                   $qtrees[$i]=$qtree.split("!");
                                                                   $item = New-Object System.Object
                                                                   $item| Add-Member -MemberType NoteProperty -Name SVM -value $qtrees[$i][0] -Force
                                                                   $item| Add-Member -MemberType NoteProperty -Name Volume -value $qtrees[$i][1] -Force
                                                                   $item| Add-Member -MemberType NoteProperty -Name User -value $qtrees[$i][3] -Force
                                                                   $item| Add-Member -MemberType NoteProperty -Name Used -value $qtrees[$i][4] -Force
                                                                   $item| Add-Member -MemberType NoteProperty -Name Limit -value $qtrees[$i][5] -Force
                                                                   $item = $item| select *, @{Name = 'PercentageUsed';Expression={[math]::round(100*($_.used)/($_.limit),2)}}
                                                                   $items+=$item|? {$_.limit -ne "0GB"} #remove erroneous entries which cause problems in the CSV
                                                                   $i++
                                                                  }
                                }

                #$items | Export-Csv -Path $CSV -Force #If we're doing everything in one script we probably don't need to export a csv and just handle it internally instead

                }
    Else {write-host "No SSH commands were ran due to SSH connection error"}
    } 

#Ensure the monitoring check is ran only once every morning at 0700                          
If (Test-Path -path $CSV){ try{$lastmodified = (Get-Item -path $CSV -ea Stop).LastWriteTime }
                           catch {throw "error handling csv file"} 
                           If (($lastmodified.addhours(2) -le $date) -and ($date.Hour -eq 7)){
                                                                    getnetappreport
                                                                    
                                                                   }
                                                                   readreport
                         }
                                                                   
Elseif (!(Test-Path -path $CSV)){ 
                                      getnetappreport
                                      readreport}
    


