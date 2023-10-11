#Enforce TLS 1.2 minimum for web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

[string]$Department= (Read-Host "Enter name of department").ToLower()
[string]$StorageAccount=("uobprdsaaf$($department)").ToLower()
[string]$ResourceGroup="rg-prd-sa-ddat-af-$($Department)"
Write-Host "The following will be created in Azure:"
Write-Host " -  Storage account: $($StorageAccount) "
Write-Host " -  Resource group: $($ResourceGroup)`n"
pause

$YourName=Read-Host "Enter your name (for tagging purposes)"
$ProjectName=Read-Host "Enter name of project (for tagging purposes i.e. `"Departmental files for..`")"
$ProjectCode=Read-Host "Enter code of project (for tagging and billing purposes, leave blank to use cloud budget code CA-CS1STG)"
[string]$accountType_input=(Read-Host "`nEnter type of storage account to deploy:`n`t`"S`" for Standard`nor`n`t`"P`" for Premium `nDefault (leave blank) = `"S`" (Standard)").ToLower()
Switch ($accountType_input) {

 ""               {$accountType="Standard_RAGRS"} 
 "s"              {$accountType="Standard_RAGRS"}
 "standard"       {$accountType="Standard_RAGRS"}
 "Standard_ragrs" {$accountType="Standard_RAGRS"}

 "p"              {$accountType="Premium_ZRS"}
 "premium"        {$accountType="Premium_ZRS"}
 "premium_zrs"    {$accountType="Premium_ZRS"}

 default     {     Write-Host "WARN: Storage account type validation failed, script will default to deploying storage account type `'Standard`' (Standard_RAGRS)" -ForegroundColor yellow;pause
                   $accountType="Standard_RAGRS"}
}

[string]$largeFileSharesState_input=(Read-Host "`nEnable ability to create large file shares on the storage account? (Setting cannot be changed once set)`n`tEnter:`n`t`t`"Yes`" to enable ability to create 100TiB shares`n`t`t`"No`" to limit ability to create 5TiB shares only`n`tDefault (leave blank) = `"No`"").ToLower()

switch ($largeFileSharesState_input) {

        "" {$largeFileSharesState="Enabled";$accountType="$(($accountType -split "_")[0])_ZRS"}
        "yes" {$largeFileSharesState="Enabled";$accountType="$(($accountType -split "_")[0])_ZRS"}
        "y" {$largeFileSharesState="Enabled";$accountType="$(($accountType -split "_")[0])_ZRS"}
   
      "n" {$largeFileSharesState="Disabled"}
      "no" {$largeFileSharesState="Disabled"}
default {Write-Host "WARN: Large file share state validation failed, script will default to deploying storage account with large file shares disabled" -ForegroundColor yellow;pause
            $largeFileSharesState="Disabled"}
}

Write-Host "`nDeployment will now start`n" ; pause

Set-Location "\\vresources.campus.bath.ac.uk\Software"

[string]$Template= "\\vresources.campus.bath.ac.uk\Software\DDAT\Azure\Templates\StorageAccountTemplate.json"
[string]$Parameters= get-content -Path "\\vresources.campus.bath.ac.uk\Software\DDAT\Azure\Templates\StorageAccountParameters.json"

if ((Get-AzAccessToken -ErrorAction SilentlyContinue).ExpiresOn.datetime -lt (get-date)) {Disconnect-AzAccount;Connect-AzAccount}
if ([string]::IsNullOrEmpty($(Get-AzContext).Account)) {Connect-AzAccount}

$location="uksouth"

if ((Get-AzResourceGroup -Name $ResourceGroup -Location $location -ErrorAction SilentlyContinue) -eq $true) {exit}
#New-AzResourceGroup -Name $ResourceGroup -Location $location


$Parameters_json= ConvertFrom-Json $Parameters
$Parameters_json.parameters.storageaccountname.value = $StorageAccount
$Parameters_json.parameters.privateLinkResource.value = "/subscriptions/ID-REDACTED/resourceGroups/$($ResourceGroup)/providers/Microsoft.Storage/storageAccounts/$($StorageAccount)"
$Parameters_json.parameters.privateEndpointName.value = "$($StorageAccount)-pe1"


if (![string]::IsNullOrEmpty($ProjectCode)) {$Parameters_json.parameters.ProjectCode.value = $ProjectCode}
if (![string]::IsNullOrEmpty($ProjectName)) {$Parameters_json.parameters.ProjectName.value = $ProjectName}
if (![string]::IsNullOrEmpty($YourName)) {$Parameters_json.parameters.TechnicalOwner.value = $YourName}
if (![string]::IsNullOrEmpty($accountType)) {$Parameters_json.parameters.accountType.value = $accountType}
if (![string]::IsNullOrEmpty($largeFileSharesState)) {$Parameters_json.parameters.largeFileSharesState.value = $largeFileSharesState}

$Parameters_New = $Parameters_json | ConvertTo-Json
($Parameters_New).Replace("\u0027","'") | Out-File -FilePath "C:\temp\$($StorageAccount)SA_Parameters.json" -Force
$Parametersfile = "C:\temp\$($StorageAccount)SA_Parameters.json"
Copy-Item $Template "C:\temp\$($StorageAccount)SA_Template.json"
$Templatefile= "C:\temp\$($StorageAccount)SA_Template.json"

New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $Templatefile -TemplateParameterFile $Parametersfile -Verbose

Set-Location "C:\"

$Parametersfile | Remove-Item -Force
$Templatefile | Remove-Item -Force
