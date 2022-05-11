Function Configure-NewAZShare {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(Mandatory=$True,HelpMessage="The name of the storage account")] [string]$StorageAccount,
    [Parameter(Mandatory=$True,HelpMessage="The name of the resourcegroup")] [string]$ResourceGroup,
    [Parameter(Mandatory=$True,HelpMessage="The name of the file share")] [string]$Share,
    [Parameter(Mandatory=$false,HelpMessage="The name of an additional admin group in AD")][string]$AdminGroup,
    [Parameter(Mandatory=$false,HelpMessage="The name of the subscription (if different from default")][string]$Subscription)
    
    [string]$Default_AZSubscription="Set default subscription here"
    [string]$Default_StorageAdminGroup="set default xxxx-admins group here"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrEmpty($(Get-AzContext).Account)) {Connect-AzAccount}

if ([string]::IsNullOrEmpty($Subscription)) {#If context hasn't been specified
                                             Write-Host "Parameter '-subscription' not set, defaulting to: uob-prd" -ForegroundColor Yellow
                                             try {
                                                  Set-AzContext $Default_AZSubscription | Out-Null
                                                  $AZcontext=(Get-AzContext).subscription.name
                                                  }
                                                  catch {Throw "Error setting context to subscription: $($Default_AZSubscription)"}
                                            }

                                            else {#If context has been specified
                                                  try {
                                                       Set-AzContext $Subscription | Out-Null
                                                       $AZcontext=(Get-AzContext).subscription.name
                                                       }
                                                       catch {Throw "Error setting context to subscription: $($subscription)"} 

Write-Host "Finding resource group $($ResourceGroup) in $($AZcontext).." -NoNewline
try {
     $AZResourceGroup = Get-AzResourceGroup -Name $ResourceGroup -ea SilentlyContinue
    }
    catch { Throw "ERROR unable to find Resource Group: $ResourceGroup"}
Write-Host "Done" -ForegroundColor Green
#Write-Host $AZResourceGroup

Write-Host "Finding storage account $($StorageAccount).." -NoNewline
try {
     $AZStorageAccount = Get-AzStorageAccount -ResourceGroupName $AZResourceGroup.ResourceGroupName -StorageAccountName $StorageAccount -ea SilentlyContinue
    }
    catch { Throw "ERROR unable to find Storage Account: $StorageAccount"}
Write-Host "Done" -ForegroundColor Green


Write-Host "Finding a valid kerberos key for temporary drive mapping.." -NoNewline
try {
     $key = (Get-AzStorageAccountKey -ResourceGroupName $AZResourceGroup.ResourceGroupName -StorageAccountName $AZStorageAccount.StorageAccountName | select -first 1).value
     $Key_PW = $Key | ConvertTo-SecureString -AsPlainText -force
    }
    catch {Throw "ERROR getting kerberos key for: $StorageAccount" }
Write-Host "Done" -ForegroundColor Green

try {
     $PS_Drive_params = @{ 
         Name = "Z" #find an unused ps drive maybe?
         PSProvider = "FileSystem"
         Root = "\\$($AZStorageAccount.StorageAccountName).file.core.windows.net\$($Share)"
         Persist = $false
         Credential = [pscredential]::new("localhost\$($AZStorageAccount.StorageAccountName)",$Key_PW)
     }

        Write-Host "Mapping drive using keberos key.." -NoNewline
        New-PSDrive @PS_Drive_params | Out-Null
    }
    catch { Throw "ERROR mapping drive: $StorageAccount"}
Write-Host "Done" -ForegroundColor Green

try {
     Set-Location "$($PS_Drive_params.name):"
    }
    catch {Throw "ERROR Navigating to new drive mapping: $($PS_Drive_params.name)"}


Write-Host "Setting ACLs on root of $($share) share for.."
try {
    $ACL=get-acl .
    Write-Host "    $($Default_StorageAdminGroup).." -NoNewline
    $accessrule1 = New-Object System.Security.AccessControl.FileSystemAccessRule(
          $($Default_StorageAdminGroup),
          [System.Security.AccessControl.FileSystemRights]::FullControl,
          (
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit +
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
          ),
          [System.Security.AccessControl.PropagationFlags]::None,
          [System.Security.AccessControl.AccessControlType]::Allow
        )
    $ACL.AddAccessRule($accessrule1)
    Set-Acl -Path . $ACL
    }
    catch {Throw "ERROR setting ACLs for $($Default_StorageAdminGroup)"}
Write-Host "Done" -ForegroundColor Green
Write-Host ""

Write-Host "Removing unecessary ACLS.." -NoNewline
try {
    $NewACL1=get-acl .
        $Rules=$NewACL1.GetAccessRules($true,$true, [System.Security.Principal.NTAccount])|? {($_.identityreference -ne "BUILTIN`\Administrators") `
                                                                                         -and ($_.identityreference -ne "CAMPUS`\$($Default_StorageAdminGroup)") `
                                                                                         -and ($_.identityreference -ne "NT AUTHORITY\SYSTEM")
                                                                                                                        }
        foreach ($rule in $rules) {$NewACL1.RemoveAccessRule($rule) | Out-Null}
    
    Set-Acl -Path . $NewACL1
    }
    catch {Throw "ERROR removing unecessary ACLs on root of share $($share)"}
Write-Host "Done" -ForegroundColor Green


Write-Host "Applying new ACLS for Authenticated Users.." -NoNewline
try {
    $NewACL2=get-acl .
    $accessrule2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
          "NT AUTHORITY\Authenticated Users",
          [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
          (
            [System.Security.AccessControl.InheritanceFlags]::None
          ),
          [System.Security.AccessControl.PropagationFlags]::None,
          [System.Security.AccessControl.AccessControlType]::Allow
        )
   
    $NewACL2.AddAccessRule($accessrule2)
    Set-Acl -Path . $NewACL2
    }
    catch {Throw "Error applying new ACLS for Authenticated Users"}
Write-Host "Done" -ForegroundColor Green


if (![string]::IsNullOrEmpty($($AdminGroup))) {
Write-Host "Applying new ACLS for $($AZAdminGroup).." -NoNewline
try {
    $NewACL3=get-acl .
    $accessrule3 = New-Object System.Security.AccessControl.FileSystemAccessRule(
          $AZAdminGroup.DisplayName,
          [System.Security.AccessControl.FileSystemRights]::FullControl,
          (
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit +
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
          ),
          [System.Security.AccessControl.PropagationFlags]::None,
          [System.Security.AccessControl.AccessControlType]::Allow
        )

    $NewACL3.AddAccessRule($accessrule3)
    Set-Acl -Path . $NewACL3
    }
    catch {Throw "Error applying new ACLS for $($AdminGroup)"}
Write-Host "Done" -ForegroundColor Green

} else {Write-Host "WARNING: No xxgr-admin group defined. NO ACLs will be applied for IT supporter access" -ForegroundColor Yellow}
        Write-Host ""
   

Write-Host "Navigating away from mapped drive $($PS_Drive_params.name).." -NoNewline
try {
    Set-Location C: #Unmap to prepare remove-PSDrive. Test if C: exists? maybe get system drive.
    }
    catch {Throw "ERROR unable to navigate away from temporary mapped drive $($PS_Drive_params.name)"}
Write-Host "Done" -ForegroundColor Green


Write-Host "Removing mapped drive $($PS_Drive_params.name).." -NoNewline
try {
    Remove-PSDrive -Name "$($PS_Drive_params.name)"
    }
    catch {Throw "ERROR unable to remove mapped drive $($PS_Drive_params.name)"}
Write-Host "Done" -ForegroundColor Green
Write-Host ""

Write-Host "Task complete" -ForegroundColor Green
}
}
#Export-ModuleMember -function New-ConfigureAZShare   
