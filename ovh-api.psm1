# Acces OVH API via powershell
# 
# 2013-10 Ghozlane TOUMI g.toumi@gmail.com 
# This file is released under GPL v2


<#
  OVH API query 
FIXME : move to powershell Doc style...

#for powershell 2 requires ConvertFrom-JSON.psm1
#not tested in ps3
  
## usage :
import-module ovh-api.psm1
  
# first, create app key and app secret  : see https://eu.api.ovh.com/createApp/
## API credentials : 

Init-Api -ak '<ak>' -as '<as>' -ck 'fake ck'
Get-Credential

## API access (returns Powershell objects)
Init-Api -ak '<ak>' -as '<as>' -ck '<ck>'
Query-Api -query "/cloud"
Query-Api -method PUT -query "/cloud/..." -body "{ nice : json }"
# shortcut
Query-Api GET /cloud

# raw json
Query-Api -method GET -query "/cloud" -raw

# more complex :
# get servers, extracts logical and physical data
query-api get /dedicated/server | %{ query-api get /dedicated/server/$_ } | select name, reverse, datacenter, rack 

#>

# FIXME : conditional
# Powershell 2 needs an external json converter
import-module ./ConvertFrom-JSON.psm1
# Powershell V3 has its own ConvertFrom-JSON

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


function Init-Api {
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
    Write-Verbose "Init-Api"
    $script:ak=$ApplicationKey
    $script:as=$ApplicationSecret
    $script:ck=$ConsumerKey
    if ($ApiBaseUrl) {
        $script:api=$ApiBaseUrl
    }
}


function Get-OvhSignature {
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

    Write-Debug "get-OVHSignature : $key -> hexhash"
    # "$1$" + SHA1_HEX(AS+"+"+CK+"+"+METHOD+"+"+QUERY+"+"+BODY +"+"+TSTAMP)

    return "`$1`$$hexhash"
}


# get time from ovh API standpoint.
# caches the delta
function Get-OvhTime {
    [CmdletBinding()]
    param ( )
    # get unixtime with UTC!
    $now =  [int][double]::Parse((Get-Date  -Date (get-date).touniversaltime() -u %s))
    if(!$script:timestampDelta) {
        Write-Verbose "get-OvhTime : query API Time"
        $Req = [System.Net.WebRequest]::create($script:api+"/auth/time")
        $Req.method="GET";
    
        $rs = $Req.GetResponse().GetResponseStream()
        Write-Verbose "get-OvhTime : got API Time"

        $sr =  New-Object System.IO.StreamReader($rs)
        
        $Rep=$sr.ReadToEnd()
        
        $sr.Close()
        $rs.close()
        $script:timestampDelta= $now - [int]::Parse($Rep)
    } else {
        Write-Verbose "get-OvhTime : from cache"
    }
    Write-Verbose "get-OvhTime : timestampDelta : $script:timestampDelta"
    return $now-$script:timestampDelta
}


function Query-Api {
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
    Write-Verbose "Query-Api : $method $query"
    if (-not ( $script:ck -and  $script:ak -and $script:as )) {
        write-Error "Query-Api :no credentials defined, please run init-api First"
        return
    }
    $url=$script:api+$query
    $timestamp=Get-OvhTime
    $signature=Get-OvhSignature -method $method -query $url -body $body -timestamp $timestamp
        
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
        Write-Verbose "Query-Api : done"
        $sr =  New-Object System.IO.StreamReader($rs)
        
        $Rep=$sr.ReadToEnd()
    }
    catch {
         Write-Host "Query-Api : $method $query"
         Write-Error $_
    }
    finally {
        if ($sr) {
            $sr.Close()
        }
        if ($rs) {
            $rs.Close()
        }
        if ($Rep) {
            if ($raw) {
                return $Rep   
            } else {
                return ConvertFrom-JSON($Rep)
            }
        }
    }
}

#
# helper independant :  demande un ticket (ck) avec droits et URL de validation #
# lecture sur /* ici
# FIXME : 
#   parametriser les ACL
#   gerer les erreurs
#   integrer la ck pour eviter d'avoir a refaire l'init-api...

function Get-Credential {
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

export-modulemember -function Calc-Signature, Init-Api, Query-Api, Get-Credential
