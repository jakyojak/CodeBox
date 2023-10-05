#Local Check_MK service check for SQL services
# To be ran every minute or however often CheckMK is configured

# Get all SQL services
$services = get-service |? {$_.displayname -like "SQL*"}
$service_state=$services.Status

# Define the displayname of the service check in CheckMK
$service_Displayname="SQL_Reporting_Services"
$Service_Check="SERVICE_$($service_Displayname)"

# Get the number of services that are running
$Services_running = ($service_state |? {$_ -eq "running"}).count

# If all of the SQL services are running 
If ($services_running -eq $services.count) {

# Define the "OK" service status in CHeckMK
$status = "0"

# Produce a list for the output of Service description in CheckMK
$list= foreach($Service in $services) {"\n" + "$($service.status) $($service.displayname)" -join "\n" }

# Work out the number of services not running for the graph metric
$Not_Running=($services.count - $services_running)

# Put the metric into the proper format
$metric="SQL_Services_Not_Running=$($Not_Running);1:;1:$($services.count)"

#Define the message for the service check
$msg= "Reporting services are all running:$($list)"

} else {

# Define the "Critical" service status in CHeckMK
$status = "2"

# Produce a list for the output of Service description in CheckMK
$list= foreach($Service in $services) {"\n" + "$($service.status) $($service.displayname)" -join "\n" }

# Work out the number of services not running for the graph metric
$Not_Running=($services.count - $services_running)

# Put the metric into the proper format
$metric="SQL_Services_Not_Running=$($Not_Running);1:;1:$($services.count)"

#Define the message for the service check
$msg= "Reporting services are not all running. Click $($Service_Check) to check the state of the services:$list"

}

# Write the service check components into the proper format to send back to the CheckMK monitoring server
Write-Output "$($status) $($Service_Check) $($metric) $($msg)"
