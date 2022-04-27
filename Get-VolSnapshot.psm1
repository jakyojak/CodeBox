<#
.SYNOPSIS
Checks snapshots. Code example specific to UoB.

.DESCRIPTION
The Get-VolSnapshot cmdlet provides an efficient way for searching through multiple previous version folders in Windows.

There are 3 madatory parameters and the cmdlet will do some basic checks, such as checking the path provided starts
 with '\\campus\files' or 'X:\' and whether the dates provided are within the last 90 days as snapshots aren't kept 
for any longer.


.PARAMETER Path
The path to the folder where you want to conduct the recursive search in. Needs to be surrounded in quotes.

.PARAMETER SearchString
The name of the file(s) you are searching for

.PARAMETER From
The date to search from. In format dd/MM/yyyy.

.PARAMETER To
The date to search to. In format dd/MM/yyyy. Defaults to Today.

.PARAMETER WhatIf
Performs a dry run, showing what would happen without performing any changes.

.PARAMETER Confirm
Requires confirmation on each step.

.EXAMPLE
Get-VolSnapshot

Will prompt for 4 mandatory values- Path, SearchString, From, To.

.EXAMPLE
Get-VolSnapshot -Path "X:\Chemistry\ResearchProjects\User1\Folder1\PhD Work\4 - Previous Work" -SearchString *.docx  -From 29/12/2020 -To 02/01/2021  

will search recusively in "X:\Chemistry\ResearchProjects\User1\Folder1\PhD Work\4 - Previous Work" for any .docx files from 29th December 2020 until the 2nd January 2021.


#>

Function Get-VolSnapshot {  

    [CmdletBinding(SupportsShouldProcess)]

    param (

    [Parameter(Mandatory=$True,HelpMessage="The full path of the folder to search in")] [Validatescript({
        if (($_ -ilike "\\campus\files\*") -or ($_ -ilike "x:\*")) {$true}
        else {throw "Path does not start with '\\campus\files' or 'X:\'"}
        })][string]${Path},

    [Parameter(Mandatory=$true,HelpMessage="The search string")] [string]${SearchString} = "",

    [Parameter(Mandatory=$true,HelpMessage="The date to search from")] [validatescript({            
            $Date = [datetime]::Parse($_,([Globalization.CultureInfo]::CreateSpecificCulture('en-GB')))
            if ($Date -gt (get-date).AddDays(-90)){$true}            
            else {throw "$_ is not a valid date format or is not within the last 90 days. Format is dd/MM/yyyy."}
            })][string]$from,

    [Parameter(Mandatory=$false,HelpMessage="The date to search to, Default = Today")] [Validatescript({
            $Date = [datetime]::Parse($_,([Globalization.CultureInfo]::CreateSpecificCulture('en-GB')))
            if ($Date -gt (get-date).AddDays(-90)){$true}
            else {throw "$_ is not a valid date format or is not within the last 90 days. Format is dd/MM/yyyy."}
            })][string]$to 

    )

    $fromdate = ([datetime]::Parse($from,([Globalization.CultureInfo]::CreateSpecificCulture('en-GB')))).Date #Makes sure date is in UK format
    
    if([string]::IsNullOrEmpty($to)){ #defaults to today if no "to" date specified
        $todate = (Get-Date).Date
    } else {
        $todate = ([datetime]::Parse($to,([Globalization.CultureInfo]::CreateSpecificCulture('en-GB')))).Date
    }

    if($todate -lt $fromdate){ #Make sure From is earlier than To...
        throw """From"" date is later than the ""To"" date, make sure the dates are the correct way around." 
    }

    if($todate -gt (Get-Date).Date -or $fromdate -gt (Get-Date).Date){
        throw "Future dates are not permitted" #Make sure date is not in the future, because snapshots don't exist then
    }

    $path = $path.Replace("X:","\\campus\files") #Convert to UNC

    try {
    $pathitem = Get-Item -Path $path -ErrorAction Stop #Check path exists and stores details in pathitem
    } catch {throw "Unable to find folder $path. Verfiy the path and ensure you have access."}

    If($path -ilike "\\campus\files*"){ #make sure path is within \\campus\files

        Do{ #starts parent snapshot folder finding loop
            $SSTOPlvlFol = Get-DfsnFolder -Path $pathitem.FullName -ErrorAction SilentlyContinue #Checks the path for snapshots
            if([string]::IsNullOrEmpty($SSTOPlvlFol)){
                $pathitem = $pathitem.Parent #If patch does not contain go to parent folder ready for recheck in loop
            } 
            if([string]::IsNullOrEmpty($pathitem)) { #if path becomes null or empty it has reached the end of the parent directories with no snapshots
                throw("Unable to find the snapshot top level folder. Verify the full path. If the problem persists contact the Servers and Storage team")
            }

        }until(-not [string]::IsNullOrEmpty($SSTOPlvlFol)) #keep going until it finds a snapshot

    } else {
        throw ("Path format is invalid. Ensure that the path starts with either X:\ or \\campus\files")
    }

    $suffix=$path.replace($SSTOPlvlFol.Path,"") #stores child folder path from parent snapshot folder


    $list=@()

    $FormatedFromDate = $fromdate | get-date -f dd/MM/yyyy
    $FormatedToDate = $todate | get-date -f dd/MM/yyyy

    Write-Host("`nFolder: $path")
    Write-Host("Search string: " + $SearchString + "`n")
    Write-Host("From date: " + $FormatedFromDate)
    Write-host("To date:   " + $FormatedToDate + "`n")

    $thedate = $fromdate #sets the current folder date to the from date (the first date)

    Do{ #starts folder date loop
        if ($thedate.IsDaylightSavingTime()) {  #Check if that day is during BST and adjust snapshot time to match
            $Time1 = "12.00.00"
            $Time2 = "06.00.00"
        } else {
            $Time1 = "13.00.00"
            $Time2 = "07.00.00"
        }

        $FormatedDate = $thedate | get-date -f yyyy.MM.dd

        $FolderPath1 = $SSTOPlvlFol.Path + "\@GMT-" + $FormatedDate + "-" + $Time1 + $suffix
        $FolderPath2 = $SSTOPlvlFol.Path + "\@GMT-" + $FormatedDate + "-" + $Time2 + $suffix

        $files = Get-ChildItem $FolderPath1 -Filter "*$SearchString*" -Recurse #Finds files in the path with the required filter fo the first time of day snapshot folder
        $list += $files | select @{N="File";E={$_.Name}}, @{N="SnapshotDate"; E={($thedate | get-date -f dd/MM/yyyy) + " " + $Time1.Replace(".00.00",":00")}}, @{N="SnapshotDirectory"; E={$_.DirectoryName}} -ErrorAction SilentlyContinue

        $list += "`n"

        $files = Get-ChildItem $FolderPath2 -Filter "*$SearchString*" -Recurse #Finds files in the path with the required filter fo the second time of day snapshot folder
        $list += $files | select @{N="File";E={$_.Name}}, @{N="SnapshotDate"; E={($thedate | get-date -f dd/MM/yyyy) + " " + $Time2.Replace(".00.00",":00")}}, @{N="SnapshotDirectory"; E={$_.DirectoryName}} -ErrorAction SilentlyContinue        

        $list += "`n"

        $thedate = $thedate.AddDays(1) #increments the current folder date by 1 day

    }until($thedate -eq $todate.AddDays(1)) #Keeps looping until date reaches the "to" date (the +1 day is due to the date being incremented before the file finding is done, otherwise kicks out a day early)

    return $list

}

Export-ModuleMember -Function Get-VolSnapshot
