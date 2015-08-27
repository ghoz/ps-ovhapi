# Acces OVH API via powershell
# 
# 2013-10 Ghozlane TOUMI g.toumi@gmail.com 
# This file is released under GPL v2
# 2015-08 changed API calls to be more powershell like
#
# Note: only one api credential at a time

<#
  OVH API query 
FIXME : move to powershell Doc style...

#for powershell 2 requires ConvertFrom-JSON.psm1
#not tested in ps3
  
## usage :
import-module ovh-api.psm1
  
# first, create app key and app secret  : see https://eu.api.ovh.com/createApp/
## API credentials : 

Connect-OvhApi -ak '<ak>' -as '<as>' -ck 'fake ck'
Get-OvhApiCredential

## API access (returns Powershell objects)
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
Get-OvhApi /dedicated/server | %{ get-OvhApi /dedicated/server/$_ } | select name, reverse, datacenter, rack 

#>

# Powershell V3 has its own ConvertFrom-JSON
# Powershell 2 needs an external json converter
if (-not (Get-Command ConvertFrom-JSON -errorAction SilentlyContinue))
{
    import-module ./ConvertFrom-JSON.psm1
}


# Application Key
[string] $ak = $null

# Application Secret key
[string] $as = $null

# Consumer key
[string] $ck =$null

# timestamp delta
[int]$timestampDelta=$null

# API url
[string] $api='https://eu.api.ovh.com/1.0'


function Connect-OvhApi {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True)]
        [Alias('ak')]
        [string]
            $ApplicationKey,
        [Parameter(Mandatory=$True)]
        [Alias('as')]
        [string]
            $ApplicationSecret,
        [Parameter(Mandatory=$True)]
        [Alias('ck')]
        [string]
            $ConsumerKey,
        [string]
            $ApiBaseUrl = $null
    )
    Write-Verbose "Connect-OvhApi"
    $script:ak=$ApplicationKey
    $script:as=$ApplicationSecret
    $script:ck=$ConsumerKey
    if ($ApiBaseUrl) {
        $script:api=$ApiBaseUrl
    }
}


function Get-OvhApiSignature {
    [CmdletBinding()]
    param (
        [string]
            $method,
        [string]
            $query,
        [string]
            $body,
        [string]
            $timestamp
    )
    $sha1 = New-Object System.Security.Cryptography.SHA1Managed

    $key = "$script:as+$script:ck+$method+$query+$body+$timestamp"
    $hash = $sha1.ComputeHash([Text.Encoding]::ASCII.GetBytes($key))
    $hexhash= [String]::join("", ($hash | %{ $_.toString('x2') }) )

    Write-Debug "Get-OvhApiSignature : $key -> hexhash"
    # "$1$" + SHA1_HEX(AS+"+"+CK+"+"+METHOD+"+"+QUERY+"+"+BODY +"+"+TSTAMP)

    return "`$1`$$hexhash"
}


# get time from ovh API standpoint.
# caches the delta
function Get-OvhApiTime {
    [CmdletBinding()]
    param ( )
    # get unixtime with UTC!
    $now =  [int][double]::Parse((Get-Date  -Date (get-date).touniversaltime() -u %s))
    if(!$script:timestampDelta) {
        Write-Verbose "Get-OvhApiTime : query API Time"
        $Req = [System.Net.WebRequest]::create($script:api+"/auth/time")
        $Req.method="GET";
    
        $rs = $Req.GetResponse().GetResponseStream()
        Write-Verbose "Get-OvhApiTime : got API Time"

        $sr =  New-Object System.IO.StreamReader($rs)
        
        $Rep=$sr.ReadToEnd()
        
        $sr.Close()
        $rs.close()
        $script:timestampDelta= $now - [int]::Parse($Rep)
    } else {
        Write-Verbose "Get-OvhApiTime : from cache"
    }
    Write-Verbose "Get-OvhApiTime : timestampDelta : $script:timestampDelta"
    return $now-$script:timestampDelta
}


function Invoke-OvhApi {
     param (
        [ValidateSet('GET', 'POST', 'DELETE', 'PUT', IgnoreCase = $true)]
        [Parameter(Position=0)]
        [string]
            $method = 'GET',
        [Parameter(Mandatory=$True, Position=1)]
        [string]
            $query,
        [string]
            $body,
        [switch]
            $raw
    )
    $method=$method.ToUpper()
    Write-Verbose "Invoke-OvhApi : $method $query"
    if (-not ( $script:ck -and  $script:ak -and $script:as )) {
        write-Error "no credentials defined, please run Connect-OvhApi First"
        return
    }
    $url=$script:api+$query
    $timestamp=Get-OvhApiTime
    $signature=Get-OvhApiSignature -method $method -query $url -body $body -timestamp $timestamp
        
    try { 
        $Req = [System.Net.WebRequest]::create($url)
        $Req.method=$method
        $Req.Headers.Add('X-Ovh-Application', $script:ak)
        $Req.Headers.Add('X-Ovh-Timestamp', $timestamp)
        $Req.Headers.Add('X-Ovh-Signature', $signature)
        $Req.Headers.Add('X-Ovh-Consumer', $script:ck)
    
        if ($method -eq 'PUT' -or $method -eq 'POST' ) {
            $Req.ContentType = 'application/json'
            $b=[Text.Encoding]::ASCII.GetBytes($body)
            $postStream = $Req.GetRequestStream()
            $poststream.write($b, 0, $b.length)
            $postStream.close()
        }
          
        $rs = $Req.GetResponse().GetResponseStream()
        Write-Verbose "Invoke-OvhApi : done"
        $sr =  New-Object System.IO.StreamReader($rs)
        
        $Rep=$sr.ReadToEnd()
    }
    catch {
         Write-Error "$method $query"
         Throw $_
    }
    finally {
        if ($sr) {
            $sr.Close()
        }
        if ($rs) {
            $rs.Close()
        }
    }
    if ($Rep) {
        if ($raw) {
            return $Rep
        } else {
            return ConvertFrom-JSON($Rep)
        }
    }
}

function Get-OvhApi {
     param (
        [Parameter(Mandatory=$True, Position=0)]
        [string]
            $query,
        [switch]
            $raw
    )
    Invoke-OvhApi -method GET -query:$query -raw:$raw
}

function Set-OvhApi {
     param (
        [Parameter(Mandatory=$True, Position=0)]
        [string]
            $query,
        [Parameter(Mandatory=$True)]
        [string]
            $body,
        [switch]
            $raw
    )
    Invoke-OvhApi -method POST -query:$query -body:$body -raw:$raw
}

function New-OvhApi {
     param (
        [Parameter(Mandatory=$True, Position=0)]
        [string]
            $query,
        [Parameter(Mandatory=$True)]
        [string]
            $body,
        [switch]
            $raw
    )
    Invoke-OvhApi -method PUT -query:$query -body:$body -raw:$raw
}

function Remove-OvhApi {
     param (
        [Parameter(Mandatory=$True, Position=0)]
        [string]
            $query,
        [switch]
            $raw
    )
    Invoke-OvhApi -method DELETE -query:$query -raw:$raw
}

#
# helper independant :  demande un ticket (ck) avec droits et URL de validation #
# lecture sur /* ici
# FIXME : 
#   parametriser les ACL
#   gerer les erreurs
#   integrer la ck pour eviter d'avoir a refaire l'Connect-OvhApi...

function Get-OvhApiCredential {
    $Req = [System.Net.WebRequest]::create($script:api+"/auth/credential")
    $Req.method="POST";
    $Req.Headers.Add("X-Ovh-Application", $script:ak)
    $Req.ContentType = 'application/json';
#
# RO on everything
    $q=[Text.Encoding]::ASCII.GetBytes('{
        "accessRules": [
            {
                "method": "GET",
                "path": "/*"
            }
        ]
    }')

## more complex : RO on /cloud, PUT delete on specific pca 
#    $q=[Text.Encoding]::ASCII.GetBytes('{
#        "accessRules": [
#            {
#                "method": "GET",
#                "path": "/cloud/*"
#            }, 
#            {
#                "method": "PUT",
#                "path": "/cloud/publiccloud-passport-xxxx/pca/pca-xxxx/sessions/*"
#            },
#            {
#                "method": "DELETE",
#                "path": "/cloud/publiccloud-passport-xxxx/pca/pca-xxxx/sessions/*"
#            }
#        ]
#    }')

    $dataStream = $Req.GetRequestStream();
    $datastream.write($q, 0, $q.length)
    $dataStream.close()

    
    $rs = $Req.GetResponse().GetResponseStream()
    $sr =  New-Object System.IO.StreamReader($rs)
    
    $Rep=$sr.ReadToEnd()
    
    $sr.Close()
    $rs.close()

    $Rep
}

export-modulemember -function  Connect-OvhApi, Get-OvhApiCredential,  Invoke-OvhApi, Get-OvhApi, Set-OvhApi, New-OvhApi, Remove-OvhApi 
