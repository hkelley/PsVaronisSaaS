
Function Get-VaronisDAToken {

param (
       [System.Uri]  $VaronisBaseUrl
     , [string] $ApiKey
)
    
    $body = @{
        grant_type = "varonis_custom"
    } 

    $headers = @{
        'x-api-key' = $ApiKey
    }

    $url = "{0}api/authentication/api_keys/token" -f  $VaronisBaseUrl.AbsoluteUri

    if($ret = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -ContentType "application/x-www-form-urlencoded" ) {
        return $ret
    }
}

Function Invoke-VaronisDAGraphQLQuery {
    param (
           [System.Uri]  $VaronisBaseUrl
         , [pscustomobject] $Token
         , [string] $Query 
    )

    $headers = @{
        'Authorization' = "{0} {1}" -f $Token.token_type,$Token.access_token
    }

    $url = "{0}api/graphql" -f  $VaronisBaseUrl.AbsoluteUri

    $body = @{
      query = $Query
    } | ConvertTo-Json -Compress
    
    Write-Verbose $url
    Write-Verbose $body
    try{
      $ret = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType 'application/json' -Body $body

      return $ret

      if($ret.errors.message) {
        throw  $ret.errors.message
      } else {
        return $ret.data
      }
      
    } catch [System.Net.WebException] {
      Get-HttpException $_.Exception
    }
}

Function Get-VaronisDAScheduledSearches {
    param (
           [System.Uri]  $VaronisBaseUrl
         , [pscustomobject] $Token
         , [string] $ScheduledSearch_FilterInput  
    )

$graphqlQuery = @"
query ScheduledSearches {
  scheduledSearches {
    id
    name
    description
    enabled
    schedule {
      summary
    }
    linkedSavedSearches {
      id
      name
    }
  }
}
"@

  Invoke-VaronisDAGraphQLQuery -VaronisBaseUrl $VaronisBaseUrl -Token $Token -Query $graphqlQuery
}

Function Get-VaronisDAScheduledSearcheExecutions {
  param (
         [System.Uri]  $VaronisBaseUrl
       , [pscustomobject] $Token
       , [int] $ScheduledSearchId
  )

$graphqlQuery = @"
query ScheduledSearchExecutions{
  scheduledSearchExecutions(scheduledSearchIds: [$ScheduledSearchId]) {
    id
    status
    time
    results {
      id
      status
      containsData
      dataFormat
      dataUrl
      rowCount
      businessOwner {
        id
        name
      }
    }    
  }
}
"@

Invoke-VaronisDAGraphQLQuery -VaronisBaseUrl $VaronisBaseUrl -Token $Token -Query $graphqlQuery
}

Function Get-VaronisScheduledReportExecutionFile {
  param (
         [System.Uri]  $VaronisReportUrl
       , [pscustomobject] $Token
       , [System.IO.FileInfo] $OutFolder
  )

  $headers = @{
      'Authorization' = "{0} {1}" -f $Token.token_type,$Token.access_token
  }

  $qargs = [System.Web.HttpUtility]::ParseQueryString($VaronisReportUrl.Query)
  $outFile = Join-Path -Path $OutFolder -ChildPath $qargs["filename"]

  Write-Warning $VaronisReportUrl
  Write-Warning $outFile

  Invoke-WebRequest -Headers $headers -Uri $VaronisReportUrl -OutFile $outFile

  return $outFile
}

Function Get-HttpException {
  param (
    [System.Net.WebException] $Ex
  )

  $s = $Ex.Response.GetResponseStream()
  $s.Position = 0;
  $sr = New-Object System.IO.StreamReader($s)
  $err = $sr.ReadToEnd()
  $sr.Close()
  $s.Close()
  
  $h = $_.Exception.Response.Headers 
  
  $h.keys | %{
      Write-Warning ("{0}   {1}" -f $_,$h[$_])
  }
  
  if($retrySecs = $_.Exception.Response.Headers["Retry-After"] )   {
      $newMessage = ("Rate Limit ({1}) hit.  Resume after {0:u}" -f (Get-Date).AddSeconds($retrySecs),$_.Exception.Response.Headers["X-RateLimit-Total"])
  } elseif(      [int]$_.Exception.Response.StatusCode -ge 400 `
          -and [int]$_.Exception.Response.StatusCode -lt 500 )  {
      $newMessage = ("HTTP {0} {1} thrown by {2} at line {3} - {4}" -f $_.Exception.Response.StatusCode,$_.Exception.Response.StatusCode.value__,$_.Exception.Response.ResponseUri.AbsoluteUri,$_.InvocationInfo.ScriptLineNumber, $err)
  }
  
  $newException.Message = $newMessage
  throw $newException
}

