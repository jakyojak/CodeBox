#   Uses EWS to connect to $Mailbox, searches for file matching $Subject from the last weeks worth of e-mails in inbox, perfoms a download and writes the attachment to disk.
#
#   NOTES
# - Set up a scheduled task to run weekly
# - Probably ran from server so will need internet/proxy set up for access to outlook.office365.com
# - WebServices.dll can be stolen from an outlook office installation
# - $Service_Account obviously needs access to the mailbox
# - Password for the service account that has access to the mailbox needs hashing whilst logged on to the same computer that will run this script
#   Create the hashed password by running:
#        read-host -assecurestring | convertfrom-securestring | out-file $Password_File

#Path to DLL file, probably this.
[string]$DLL_File = "C:\Program Files (x86)\Microsoft Office\Office16\ADDINS\Microsoft Power Query for Excel Integrated\bin\Microsoft.Exchange.WebServices.dll"

#Mailbox to download from
[string]$Mailbox = "User@domain.com"

#Attachment name. Used in case e-mail has more than one file attached.
[string]$Attachment_Name = "Name of attachment.doc"

#Service_Account
[string]$Service_Account = "svc_user@domain.com"

#Subject to search for
[string]$Subject = "Subject line from e-mail"

#Hashed password file
[string]$Password_File = "C:\Path\to\hashed\password\file.txt"

#Download directory for attachment
[string]$localDirectory = "C:\Path\to\write\attachment\ "

#Search for e-mails up to a week ago
[int]$Num_Days_Ago = 7

####################################################################
#          Everything below here shouldn't need editing            #
####################################################################

Import-Module -name $DLL_File

#Decrypt password
$SecureString = Get-Content  -Path $Password_File | ConvertTo-SecureString
$AccountPW=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString))

#Force SSL handshake using v1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Mailbox searchfilter date begin
$DateAfter = (get-date).AddDays(-($Num_Days_Ago))

#Mailbox searchfilter date end
$DateBefore = (get-date) 
    
    #Connect to mailbox in EWS
    $exchService = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService
    $exchService.Credentials = New-Object Microsoft.Exchange.WebServices.Data.WebCredentials($Service_Account,$AccountPW)
    $exchService.TraceEnabled = $true
    $exchService.url = "https://outlook.office365.com/EWS/Exchange.asmx"
   
    #Select the folder
    $folderid = new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox, $Mailbox)  
    $inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($exchService, $folderid)
    
    #Search filters
    $Sf_sub = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.ItemSchema]::Subject, $Subject)
    $Sf_HA = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::HasAttachments, $true)
    $Sf_DateAfter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsGreaterThan([Microsoft.Exchange.WebServices.Data.ItemSchema]::DateTimeReceived, $DateAfter)
    $Sf_DateBefore = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsLessThan([Microsoft.Exchange.WebServices.Data.ItemSchema]::DateTimeReceived, $DateBefore)
    
    #Make all filters inclusive and add to collection
    $sfCollection = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+SearchFilterCollection([Microsoft.Exchange.WebServices.Data.LogicalOperator]::And)
    $sfCollection.Add($Sf_sub)
    $sfCollection.Add($Sf_HA)
    $sfCollection.Add($Sf_DateAfter)
    $sfCollection.Add($Sf_DateBefore)

    #Number of Mail objects to find. Should download the latest e-mail with subject matching $Subject
    $view = New-Object Microsoft.Exchange.WebServices.Data.ItemView(1)
    
    #Result
    $FoundItems = $inbox.FindItems($sfCollection,$view)

    #Perform download to disk
    foreach($miMailItems in $FoundItems.Items){
        
        #($miMailItems.Subject -like $Subject) probably not needed now
    	If ($miMailItems.Subject -like $Subject) {$miMailItems.Load()}
        $miMailItems.DateTimeReceived
    	foreach($attach in $miMailItems.Attachments){
            if ($attach.Name -like $Attachment_Name) { 

    write-host $attach.name

    		$attach.Load()
    		$fiFile = new-object System.IO.FileStream(($localDirectory + “\” + $attach.Name.ToString()), [System.IO.FileMode]::Create)
    		$fiFile.Write($attach.Content, 0, $attach.Content.Length)

    write-host ("Downloaded Attachment : " + (($localDirectory + “\” + $attach.Name.ToString())))

    		$fiFile.Close()
    write-host ("Saving attachment as Attachment : " + (($localDirectory + “\” + $attach.Name.ToString())))
            }
    	}
    }

#Handle downloaded file...
# $fiFile.name | do-something
