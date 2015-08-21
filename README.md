# ps-ovhapi
Powershell helper to acces OVH REST API https://api.ovh.com

## Requirements
* powershell > v2
* provided `ConvertFrom-JSON.psm1` file for powershell V2 (stolen from  https://powershelljson.codeplex.com)
* OVH API Application key and secret : https://eu.api.ovh.com/createApp/

## Limitations : 
* credentials request in Get-OvhApiCredential is hard coded to allow GET on /*
* Only one api credentials at a time (stored in script scope)
* body for PUT and POST has to be in json

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

# shortcuts for rest methods
Invoke-OvhApi GET /cloud
Get-OvhApi /cloud

Invoke-OvhApi PUT  "/cloud/..." -body "{ nice : json }"
New-OvhAPI  "/cloud/..." -body "{ nice : json }"

Invoke-OvhApi POST  "/cloud/..." -body "{ nice : json }"
Set-OvhAPI  "/cloud/..." -body "{ nice : json }"

Invoke-OvhApi DELETE  "/cloud/..."
Remove-OvhAPI  "/cloud/..."

# Returning raw json
Invoke-OvhApi -method GET -query "/cloud" -raw

# more complex :
# get servers, extracts logical and physical data
Get-OvhApi /dedicated/server | %{ Get-OvhApi /dedicated/server/$_ } | select name, reverse, datacenter, rack 
```
