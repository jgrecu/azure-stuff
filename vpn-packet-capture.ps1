param (
    [string]$s = $(throw "parameter missing, -s SubscriptionID is required"),
    [switch]$start,
    [switch]$stop
)

function Login($subscriptioID)
{
    $subContext = Get-AzContext
    if (!$subContext -or ($subContext.Subscription.Id -ne $subscriptioID)){
        Echo "`n`tSubscription ID '$subscriptioID' is not connected.`n"
        Connect-AzAccount -SubscriptionId $subscriptioID -UseDeviceAuthentication
    }else {
        Echo "`n`tSubscription ID '$subscriptioID' already connected.`n"
    }
}

function Start
{
    ### Search for the resource group in which the VPN gateway resides
    Echo "`n`t-- Existing virtualNetworkGateways, ResourceGroupName and Location. --`n"
    Get-AzResource -ResourceType Microsoft.Network/virtualNetworkGateways | Format-Table -Property name,ResourceGroupName,Location
    
    ### Define the resource group, filter and vpn gateway variables
    $rgname = Read-Host -Prompt 'What is the VPN resource group from above? '
    $vpngw = Read-Host -Prompt 'What is the VPN gateway name from above? '

    $filterchoice = Read-Host -Prompt 'Do you want to choose the filter (YES) / or go with the default all TCP (NO) ? (YES/NO) '
    if ($filterchoice -eq "YES") {
        Echo "`n`t-- Your answer was YES, lets create the filter for you!`n"
        $srcIP = Read-Host -Prompt 'Please input the source (SAP side) IP/subnet in CIDR notation: '
        $dstIP = Read-Host -Prompt 'Please input the destination (customer side) IP/subnet in CIDR notation: '
        $filter = "{`"TracingFlags`":11,`"MaxPacketBufferSize`":120,`"MaxFileSize`":500,`"Filters`":[{`"SourceSubnets`":[`"" + $srcIP +"`",`"" + $dstIP +"`"],`"DestinationSubnets`":[`"" + $dstIP +"`",`"" + $srcIP +"`"],`"TcpFlags`":-1,`"Protocol`":[6],`"CaptureSingleDirectionTrafficOnly`":false}]}"
        Echo "The filter is: "`t$filter`n
    }
    else {
        Echo "`n`t-- Your answer was NO, you will use the generic filter!`n"
        $filter = "{`"TracingFlags`": 11,`"MaxPacketBufferSize`": 120,`"MaxFileSize`": 500,`"Filters`" :[{`"CaptureSingleDirectionTrafficOnly`": false}]}"
        Echo "The filter is: "`t$filter`n
    }
    ### Start the packet capture
    Echo "`n`t-- Starting the packet capture, please wait... --`n"
    
    Start-AzVirtualnetworkGatewayPacketCapture -ResourceGroupName $rgname -Name $vpngw -FilterData $filter
    
    Echo "`n`t-- The packet capture started, please do not forget to stop it after you finish replicating the desired connectivity.`n`tFor that please run './vpn-packet-capture.ps1 -s $subscriptioID -stop' script and follow the instructions --`n"
}


function Stop
{
    ### Start powershell and login into azure
    Echo "`nThe expectation is that you are running this script after the './vpn-packet-capture.ps1 -s $subscriptioID -start' and you are using the same SubscriptionID..."
    ### Search for all resource group in which the VPN gateway resides in
    Echo "`n`t-- Existing virtualNetworkGateways, ResourceGroupName and Location. --`n"
    Get-AzResource -ResourceType Microsoft.Network/virtualNetworkGateways | Format-Table -Property name,ResourceGroupName,Location

    $rgname = Read-Host -Prompt 'What is the VPN resource group name? COPY/PASTE from above '
    ### Define the vpn gateway name variable
    $vpngw = Read-Host -Prompt 'What is the VPN gateway name? COPY/PASTE from above '

    ### Get the location variable
    $loc = Get-AzResource -ResourceGroupName $rgname -ResourceType Microsoft.Network/virtualNetworkGateways
    $location = $loc.Location

    $storeName = $rgname.replace('-','')
    ### Create the storage account if it doesn't exist
    $stor = Get-AzResource -ResourceGroupName $rgname -ResourceType Microsoft.Storage/storageAccounts -Name $storeName -ErrorAction Ignore

    if ($stor.Name -eq $storeName) {
        Echo "`n`t-- You already got the $storeName storage account, it will be used to store the pcap files...`n"
    }
    else {
        Echo "`n`t-- You don't have the $storeName storage account, it will be created! it will be used to store the pcap files...`n"
        New-AzStorageAccount -SkuName Standard_LRS -Kind BlobStorage -Location $location -ResourceGroupName $rgname -Name $storeName -AccessTier Hot -EnableHttpsTrafficOnly $true
    }
    $containerName = "packetcaptureresults"
    $context = $(New-AzStorageContext -StorageAccountName $storeName -StorageAccountKey $(Get-AzStorageAccountKey -ResourceGroupName $rgname -Name $storeName)[0].Value)
    ### Create the container if it doesn't exist
    $storcont = $(Get-AzStorageContainer -Name $containerName -Context $context -ErrorAction Ignore).Name

    if ($storcont -eq $containerName) {
        Echo "`n`t-- You already got the 'packetcaptureresults' container, it will be used to store the pcap files...`n"
    }
    else {
        Echo "`n`t-- You don't have the 'packetcaptureresults' container, it will created! it will be used to store the pcap files...`n"
        New-AzStorageContainer -Name $containerName -Context $context
    }
    ### Get the new SASURL
    $now=Get-Date
    $sasurl = New-AzStorageContainerSASToken -Name $containerName -Context $context -Permission "rwd" -StartTime $now.AddHours(-1) -ExpiryTime $now.AddDays(1) -FullUri

    ### Stop the packet capture
    Echo "`n`t-- Stopping the packet capture, please wait... --`n"
    
    Stop-AzVirtualNetworkGatewayPacketCapture -ResourceGroupName $rgname -Name $vpngw -SasUrl $sasurl
    
    Echo "`n`t-- The packet capture has been stopped, please go to Azure portal and get the file from '$storeName' storrage account in '$containerName'container,`n`twhich can be found in '$rgname' resource group --"
}
$subscriptioID = $s

#### Select-AzSubscription -SubscriptionId $subscriptioID # moet one - 005617a9-c067-4aee-a9ac-c48e1868216a
Login($subscriptioID)
#
if ($start -eq $true) { 
    Echo "`n You chose START so we are taking you through starting the packet capture`n"
    Start
}
elseif ($stop -eq $true) {
    Echo "`n You chose STOP so we are taking you through stopping the packet capture`n"
    Stop
}
else {
    Echo "`nYou need to choose either -start or -stop at the runtime`n"
}
