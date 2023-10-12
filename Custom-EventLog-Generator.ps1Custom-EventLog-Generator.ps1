#Custom event log generator script
#Requires <Custom Event Log Name>.man file having been saved from ECMANGen.exe. If you have the SDK ECMANGen.exe can be found in C:\Program Files (x86)\Windows Kits\10\bin\10.0.15063.0\x64\ecmangen.exe or appropriate build number (replace 10.0.15063.0 as appropriate).

#Prepare vars
If (!($Dir) -and !($ResourceName)){
$Dir= Read-Host "Enter working Directory (where the .man file is)"
$ResourceName=Read-Host "Enter message/file name from .man file"
$ResourceName.replace(".man","").replace(".dll","")
}

#Prepare args
$arguments1="$dir\$ResourceName.man"
$arguments2="-css $ResourceName.DummyEvent $dir\$ResourceName.man"
$arguments3="$dir\$ResourceName.rc"
$arguments4="/win32res:$dir\$ResourceName.res /unsafe /target:library /out:$dir\$ResourceName.dll $dir\$ResourceName.cs"

#Start threadded jobs for quicker processing
$job1= Start-Job -Name Myjob1 {Set-Location $using:Dir; Start-Process "C:\Program Files (x86)\Windows Kits\10\bin\10.0.15063.0\x86\mc.exe" $using:arguments1 -Wait -PassThru} | Wait-Job | Remove-Job
$job2= Start-Job -Name Myjob2 {Set-Location $using:Dir; Start-Process "C:\Program Files (x86)\Windows Kits\10\bin\10.0.15063.0\x86\mc.exe" $using:arguments2 -Wait -PassThru} | Wait-Job | Remove-Job
$job3= Start-Job -Name Myjob3 {Set-Location $using:Dir; Start-Process "C:\Program Files (x86)\Windows Kits\10\bin\10.0.15063.0\x86\rc.exe" $using:arguments3 -Wait -PassThru} | Wait-Job | Remove-Job
$job4= Start-Job -Name Myjob4 {Set-Location $using:Dir; Start-Process "C:\tools\Roslyn46\csc.exe" $using:arguments4 -Wait -PassThru} | Wait-Job | Remove-Job

#Copy the generated files .rc .res .cs .h .dll (including the original .man file and paste to C:\Windows\System32 on the machine where the custom event log is to be created.
#
#If you are updating an existing log folder then you will first need to open powershell as an administrator and run
#  wevtutil um c:\Windows\system32\<Custom Event Log Name>.man
#  For example wevtutil um c:\Windows\system32\Forwarded_System.man
#
#To add the new log to event viewer run
#  wevtutil im c:\Windows\system32\<Custom Event Log Name>.man 
#  For example wevtutil im c:\Windows\system32\Forwarded_System.man

