#Let's track AD object deletions. Ran daily.

Write-Host "Any errors should show up here in the log"
Write-Host ""
$date=(get-date)
[string]$CSV_ADObjects_Yesterday = "C:\Reports\ADObjects\ADObjects_Yesterday.csv"
[string]$CSV_ADObjects_Today = "C:\Reports\ADObjects\ADObjects_Today.csv"
[string]$Deleted_ADObjects_CSV = "C:\Reports\ADObjects\ADObjects_Deleted.csv"

$ADObjects_Yesterday = Import-Csv $CSV_ADObjects_Today #$CSV_ADObjectFiles_Today will be yesterday's results when this function next runs. This function only runs once per day.

$ADObjects = @()
$User_Objects = Get-ADUser -filter {name -like "*"} -Properties name,sid,displayname,description,created | select name,sid,displayname,description,@{N="ObjType";E={"User"}},@{N="DateCreated";E={($_.created | get-date -Format "dd/MM/yyyy")}} | Sort-Object -Property name
$Group_Objects = Get-ADGroup -filter {name -like "*"} -Properties name,sid,displayname,description,created | select name,sid,displayname,description,@{N="ObjType";E={"Group"}},@{N="DateCreated";E={($_.created | get-date -Format "dd/MM/yyyy")}} | Sort-Object -Property name
$Computer_objects=  Get-ADComputer -filter {name -like "*"} -Properties name,sid,displayname,description,created | select name,sid,displayname,description,@{N="ObjType";E={"Computer"}},@{N="DateCreated";E={($_.created | get-date -Format "dd/MM/yyyy")}} | Sort-Object -Property name

$ADObjects+= $User_Objects
$ADObjects+= $Group_Objects
$ADObjects+=$Computer_objects

$ADObjects_Today = $ADObjects

$Comparison = Compare-Object -ReferenceObject @($ADObjects_Yesterday | Select-Object) -DifferenceObject @($ADObjects_Today | Select-Object) -IncludeEqual -Property SID

$Comparison_joined = Join-Object -Left $ADObjects_Yesterday -Right $Comparison -LeftJoinProperty SID -RightJoinProperty SID


[array]$ADObjects_Missing = @($($Comparison_joined |? {$_.sideindicator -eq "<="})| select-object) `
                                                                                                    | select *, @{N="DateDeleted";E={($date | get-date -Format "dd/MM/yyyy")}} `
                                                                                                    -ExcludeProperty sideindicator


If ($ADObjects_Missing.count -gt 0) {
                                    [array]$Deleted_ADObjects = Import-Csv $Deleted_ADObjects_CSV
                                    [array]$Deleted_ADObjects=[array]$Deleted_ADObjects+[array]$ADObjects_Missing
                                    $Deleted_ADObjects | Sort-Object -Property DateDeleted -Descending | Export-Csv $Deleted_ADObjects_CSV -NoTypeInformation -Force
                                    }


$ADObjects_Yesterday | Export-Csv $CSV_ADObjects_Yesterday -NoTypeInformation -Force
$ADObjects_Today | Export-Csv $CSV_ADObjects_Today -NoTypeInformation -Force
