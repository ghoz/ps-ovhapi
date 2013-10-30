import-module ./ConvertFrom-JSON.psm1

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
#echo $key #XXX
    $hash = $sha1.ComputeHash([Text.Encoding]::ASCII.GetBytes($key))
    $hexhash= [String]::join("", ($hash | %{ $_.toString('x2') }) )

    Write-Debug "get-OVHSignature : $key -> hexhash"
    # "$1$" + SHA1_HEX(AS+"+"+CK+"+"+METHOD+"+"+QUERY+"+"+BODY +"+"+TSTAMP)

    return "`$1`$$hexhash"
}


function Get-OvhTime {
#    [CmdletBinding()]
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
        Write-Verbose "get-OvhTime : timestampDelta : $script:timestampDelta"
    }
    return $now-$script:timestampDelta
    Write-Debug "get-OVHSignature : $key -> hexhash"
}


function Query-Api {
    param (
        [ValidateSet('GET', 'POST', 'DELETE', 'PUT', IgnoreCase = $false)]
#        [ValidateSet('GET', IgnoreCase = $false)]
        [string]
            $method = 'GET',
        [Parameter(Mandatory=$True, Position=0)]
        [string]
            $query,
        [string]
            $body,
        [switch]
            $raw
    )
    Write-Verbose "Query-Api : $method $query"
    $url=$script:api+$query
    $timestamp=Get-OvhTime
    $signature=Get-OvhSignature -method $method -query $url -body $body -timestamp $timestamp

    $Req = [System.Net.WebRequest]::create($url)
    $Req.method=$method
    $Req.Headers.Add('X-Ovh-Application', $script:ak)
    $Req.Headers.Add('X-Ovh-Timestamp', $timestamp)
    $Req.Headers.Add('X-Ovh-Signature', $signature)
    $Req.Headers.Add('X-Ovh-Consumer', $script:ck)

    if ($method -eq 'PUT' -or $method -eq 'POST' ) {
        $Req.ContentType = 'application/json'
        $b=[Text.Encoding]::ASCII.GetBytes($body)
        $postStream = $Req.GetRequestStream();
        $poststream.write($b, 0, $b.length)
        $postStream.close()
    }
         
    $rs = $Req.GetResponse().GetResponseStream()
    Write-Verbose "Query-Api : done"

    $sr =  New-Object System.IO.StreamReader($rs)
    
    $Rep=$sr.ReadToEnd()
    
    $sr.Close()
    $rs.Close()

    if ($raw) {
        return $Rep   
    } else {
        return ConvertFrom-JSON($Rep)
    }
}

#
# helper independant :  demande un ticket (ck) avec droits et URL de validation #
# lecture sur /* ici

function Get-Credential {
    $Req = [System.Net.WebRequest]::create($script:api+"/auth/credential")
    $Req.method="POST";
    $Req.Headers.Add("X-Ovh-Application", $script:ak)
    $Req.ContentType = 'application/json';

    $q=[Text.Encoding]::ASCII.GetBytes('{
        "accessRules": [
            {
                "method": "GET",
                "path": "/*"
            }
        ]
    }')

    $q=[Text.Encoding]::ASCII.GetBytes('{
        "accessRules": [
            {
                "method": "GET",
                "path": "/cloud/*"
            }, 
            {
                "method": "PUT",
                "path": "/cloud/publiccloud-passport-xxxx/pca/pca-xxxx/sessions/*"
            },
            {
                "method": "DELETE",
                "path": "/cloud/publiccloud-passport-xxxx/pca/pca-xxxx/sessions/*"
            }
        ]
    }')

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

export-modulemember -function Calc-Signature, Init-Api, Query-Api
<#
  
test OVH demo API

Init-Api -ak 'ak' -as '<ak>' -ck '<ck>'
Calc-Signature  -method 'GET' -query 'https://eu.api.ovh.com/1.0/domains/' -timestamp 1366560945

=> $1$d3705e8afb27a0d2970a322b96550abfc67bb798

#>