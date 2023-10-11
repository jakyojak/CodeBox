Remove-Variable * -ErrorAction SilentlyContinue

#Enforce TLS 1.2 for web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ADStorageaccountComputer=@()
$StorageAccountName = Read-Host "Enter storage account name" # i.e. uobprdsaaf<department>
$ResourceGroupName = Read-Host "Enter Resource group name"  # i.e. rg-prd-sa-af-ddat-<department>

if ((Get-AzAccessToken -ErrorAction SilentlyContinue).ExpiresOn.datetime -lt (get-date)) {Disconnect-AzAccount;Connect-AzAccount}
if ([string]::IsNullOrEmpty($(Get-AzContext).Account)) {Connect-AzAccount}

Set-AzContext "uob-prd"

#try/catch
$ResourceGroup=Get-AzResourceGroup -Name $ResourceGroupName -ea SilentlyContinue

#try/catch
$StorageAccount=Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ea SilentlyContinue

#Create the new AD computer
New-ADComputer -Name $StorageAccountName `
               -DisplayName $StorageAccountName `
               -Description "Azure storage account" `
               -Path "OU=Azure,OU=Storage,OU=Servers and Storage,OU=Services,DC=campus,DC=bath,DC=ac,DC=uk" `
               -Enabled $true `
               -PasswordNeverExpires $true

#Get the new AD computer object 
Do {             
$ADStorageaccountComputer = Get-ADComputer -Identity "CN=$($StorageAccountName),OU=Azure,OU=Storage,OU=Servers and Storage,OU=Services,DC=campus,DC=bath,DC=ac,DC=uk" -Properties * -ea SilentlyContinue
Start-Sleep -Seconds 1
} until ($ADStorageaccountComputer)

#Change the SPN property
Set-ADComputer `
                -Identity $ADStorageaccountComputer.distinguishedname `
                -ServicePrincipalNames @{Replace="cifs/$($StorageAccountName).file.core.windows.net"}


#Join AD computer object and Azure storage account
Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName `
-EnableActiveDirectoryDomainServicesForFile $true `
-ActiveDirectoryDomainName "campus.bath.ac.uk" `
-ActiveDirectoryNetBiosDomainName "CAMPUS" `
-ActiveDirectoryForestName "SUBDOMAIN REDACTED.bath.ac.uk" `
-ActiveDirectoryDomainGuid "GUID REDACTED" `
-ActiveDirectoryDomainsid "SID REDACTED" `
-ActiveDirectoryAzureStorageSid $($ADStorageaccountComputer.SID)

# Set the default permission on the whole storage account (new shares will have this applied to them)
$defaultPermission = "StorageFileDataSmbShareContributor"
Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -DefaultSharePermission $defaultPermission -Verbose

#Give xxx-DDaT-ServersStorage-Contrib owner access on the resourcegroup
$SS_Contrib_Group=Get-AzADGroup -DisplayName "REDACTED-DDaT-ServersStorage-Contrib"
$Role_Owner=Get-AzRoleDefinition -Name "owner"
New-AzRoleAssignment -ObjectId $SS_Contrib_Group.id -RoleDefinitionName $Role_Owner.name -Scope $ResourceGroup.ResourceId

#Apply more permissions on the storage account (for full control access for admin groups)
$Gr_NASAdmins_Group = Get-AzADGroup -DisplayName "REDACTED Group-nasadmins"
$FileShareElevatedContributorRole = Get-AzRoleDefinition "Storage File Data SMB Share Elevated Contributor" #Full Control access
New-AzRoleAssignment -ObjectId $Gr_NASAdmins_Group.id -RoleDefinitionName $FileShareElevatedContributorRole.Name -Scope $ResourceGroup.ResourceId

#Update AD computer password to that of one of the storage keys in azure
Update-AzStorageAccountADObjectPassword -RotateToKerbKey kerb1 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Confirm:$false

#Run a check
Debug-AzStorageAccountAuth -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -Verbose

#Use Configure-NewAZShare to apply default NTFS ACLS on the root and give $Gr_NASAdmins_Group access, or do manually using
#net use Y: \\uobprdsaaflibrary.file.core.windows.net\deptdata /user:localhost\uobprdsaaflibrary <insert one of the two kerberos keys here from Azure>

#Assign back up resource prd-rsv-apps-1
