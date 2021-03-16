### Start powershell and login into azure
param (
    [string]$s = $(throw "parameter missing, -s SubscriptionID is required")
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

### Select the Subscription
# Echo " -- Please get the Subscription ID from Azure portal -- `n"

# $subscriptioID = Read-Host -Prompt 'What is the subscription ID you want to connect to? '
$subscriptioID = $s
#### Select-AzSubscription -SubscriptionId $subscriptioID # moet one - 005617a9-c067-4aee-a9ac-c48e1868216a
Login($subscriptioID)
#

$nw = Get-AzResource -ResourceType Microsoft.Network/networkWatchers
$networkWatcher = Get-AzNetworkWatcher -Name $nw.Name -ResourceGroupName $nw.ResourceGroupName

# Select the resourceGroup
Get-AzResource -ResourceType Microsoft.Network/virtualNetworkGateways | Format-Table -Property name,ResourceGroupName,Location
$rgname = Read-Host -Prompt 'What is the VPN resource group name from above? '

# VPN Gateway
$vpngw = Get-AzResource -ResourceGroupName $rgname -ResourceType Microsoft.Network/virtualNetworkGateways
$targetgw = $vpngw.ResourceId

# VPN Connection
$vpnconn = Get-AzResource -ResourceGroupName $rgname -ResourceType Microsoft.Network/connections
$targetcon = $vpnconn.ResourceId

# Storage account
$storage = Get-AzResource -ResourceGroupName $rgname -ResourceType Microsoft.Storage/storageAccounts
$storageId = $storage.ResourceId
$storeName = $storage.Name

# Container
$containerName = "vpnlogs"
$context = $(New-AzStorageContext -StorageAccountName $storeName -StorageAccountKey $(Get-AzStorageAccountKey -ResourceGroupName $rgname -Name $storeName)[0].Value)
$storcont = $(Get-AzStorageContainer -Name $containerName -Context $context -ErrorAction Ignore).Name
if ($storcont -ne $containerName) {
    New-AzStorageContainer -Name $containerName -Context $context
}

$storagePath = 'https://' + $storage.Name + '.blob.core.windows.net/' + $containerName

Echo "`n`t-- Collecting logs for the VpnGateway`n"

Start-AzNetworkWatcherResourceTroubleshooting -NetworkWatcher $networkWatcher -TargetResourceId $targetgw -StorageId $storageId -StoragePath $storagePath

Echo "`n`t-- Collecting logs for the VpnConnection`n"

Start-AzNetworkWatcherResourceTroubleshooting -NetworkWatcher $networkWatcher -TargetResourceId $targetcon -StorageId $storageId -StoragePath $storagePath
