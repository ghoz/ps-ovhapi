# ps-ovhapi
Powershell helper to acces OVH REST API

## Requirements
* powershell > v2
* provided convertfrom-json.psm1 for powershell V2 (stolen from  https://powershelljson.codeplex.com)
* OVH API Application key and secret : https://eu.api.ovh.com/createApp/

## Limitations : 
* credentials request in Get-OvhApiCredential is hard coded to allow GET on /*
* Only one api credentials at a time (stored in script scope)

## Usage :
```powershell
import-module ovh-api.psm1
# Create credentials 
Connect-OvhApi -ak '<ak>' -as '<as>' -ck 'fake ck'
Get-OvhApiCredential

# API access (returns Powershell objects)
Connect-OvhApi -ak '<ak>' -as '<as>' -ck '<ck>'
Invoke-OvhApi -query "/cloud"
Invoke-OvhApi -method PUT -query "/cloud/..." -body "{ nice : json }"

# shortcuts
Invoke-OvhApi GET /cloud
Get-OvhApi /cloud

# raw json
Invoke-OvhApi -method GET -query "/cloud" -raw

# more complex :
# get servers, extracts logical and physical data
Get-OvhApi /dedicated/server | %{ Get-OvhApi /dedicated/server/$_ } | select name, reverse, datacenter, rack 
```
