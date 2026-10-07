$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$prefix = "http://127.0.0.1:8080/"
function New-AppListener {
  $created = New-Object System.Net.HttpListener
  [void]$created.Prefixes.Add($prefix)
  return $created
}
function Test-AlreadyRegistered($err) {
  $ex = $err.Exception
  while ($ex) {
    if ($ex -is [Net.HttpListenerException] -and [int]$ex.ErrorCode -eq 183) { return $true }
    $ex = $ex.InnerException
  }
  $msg = [string]$err.Exception.Message
  if ($msg -match "existing registration") { return $true }
  return $false
}
function Stop-RegisteredServer {
  $self = $PID
  $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessId -ne $self -and $_.CommandLine -and ($_.CommandLine -like "*start.ps1*")
  })
  foreach ($proc in $procs) {
    try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
  }
}
$listener = New-AppListener
function Exit-StartFailed($text) {
  Write-Host ""
  Write-Host "Could not start the local server."
  Write-Host $text
  Write-Host ""
  Write-Host "Opening index.html directly does not run the roulette."
  Write-Host "Use start.bat, and keep this window open while you play."
  exit 1
}
function Send-Text($ctx, $code, $contentType, $text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($text)
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = $contentType
  $ctx.Response.Headers.Add("Cache-Control", "no-cache")
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}

$replaced = $false
$started = $false
for ($attempt = 1; $attempt -le 6; $attempt++) {
  try {
    $listener.Start()
    $started = $true
    break
  } catch {
    if (-not (Test-AlreadyRegistered $_)) {
      Exit-StartFailed ([string]$_.Exception.Message)
    }
    try { $listener.Close() } catch {}
    if ($attempt -eq 1) { Stop-RegisteredServer }
    $replaced = $true
    Start-Sleep -Milliseconds 400
    $listener = New-AppListener
  }
}
if (-not $started) {
  Exit-StartFailed "Port 8080 is already registered, and replacing that server did not succeed."
}

Write-Host "LoL concept party roulette"
if ($replaced) { Write-Host "Replaced the server already registered on port 8080." }
Write-Host "Open $prefix  (close this window to stop)"
Start-Process $prefix

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".csv"  = "text/csv; charset=utf-8"
  ".txt"  = "text/plain; charset=utf-8"
  ".js"   = "text/javascript; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".ico"  = "image/x-icon"
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
  $reqPath = $ctx.Request.Url.AbsolutePath
  if ($ctx.Request.HttpMethod -eq "POST" -and $reqPath -eq "/api/party-enabled") {
    try {
      $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
      $body = $reader.ReadToEnd()
      $reader.Close()
      $obj = $body | ConvertFrom-Json
      $fn = [string]$obj.filename
      if ($fn -notmatch '^[A-Za-z0-9_.-]+\.csv$') {
        Send-Text $ctx 400 "application/json; charset=utf-8" '{"ok":false,"error":"bad filename"}'
        continue
      }
      $enRaw = $obj.enabled
      $on = $false
      if ($enRaw -is [bool]) { $on = [bool]$enRaw }
      else {
        $s = ([string]$enRaw).Trim().ToLowerInvariant()
        $on = ($s -eq "1" -or $s -eq "true" -or $s -eq "yes" -or $s -eq "on")
      }
      $enOut = "0"
      if ($on) { $enOut = "1" }
      $configPath = Join-Path $root "parties\config.csv"
      $lines = [IO.File]::ReadAllLines($configPath, [Text.Encoding]::UTF8)
      $newLines = New-Object System.Collections.Generic.List[string]
      $seenHeader = $false
      $updated = $false
      foreach ($line in $lines) {
        if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
          [void]$newLines.Add($line)
          continue
        }
        if (-not $seenHeader) {
          [void]$newLines.Add($line)
          $seenHeader = $true
          continue
        }
        $comma1 = $line.IndexOf(",")
        if ($comma1 -lt 0) {
          [void]$newLines.Add($line)
          continue
        }
        $fileCol = $line.Substring(0, $comma1)
        if ($fileCol -ne $fn) {
          [void]$newLines.Add($line)
          continue
        }
        $rest = $line.Substring($comma1 + 1)
        $comma2 = $rest.IndexOf(",")
        if ($comma2 -lt 0) {
          [void]$newLines.Add(($fileCol + "," + $enOut))
        }
        else {
          [void]$newLines.Add(($fileCol + "," + $enOut + $rest.Substring($comma2)))
        }
        $updated = $true
      }
      if (-not $updated) {
        Send-Text $ctx 404 "application/json; charset=utf-8" '{"ok":false,"error":"unknown party"}'
        continue
      }
      $utf8 = New-Object Text.UTF8Encoding $true
      [IO.File]::WriteAllLines($configPath, $newLines.ToArray(), $utf8)
      Send-Text $ctx 200 "application/json; charset=utf-8" ("{`"ok`":true,`"filename`":`"" + $fn + "`",`"enabled`":" + $enOut + "}")
    }
    catch {
      Send-Text $ctx 500 "application/json; charset=utf-8" '{"ok":false,"error":"save failed"}'
    }
    continue
  }

  $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath.TrimStart("/"))
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }
  $rel = $rel -replace "/", [IO.Path]::DirectorySeparatorChar
  $full = [IO.Path]::GetFullPath((Join-Path $root $rel))
  $rootFull = [IO.Path]::GetFullPath($root)
  $ok = $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)

  if (-not $ok -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
    $ctx.Response.StatusCode = 404
    $bytes = [Text.Encoding]::UTF8.GetBytes("Not Found")
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
    continue
  }

  $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
  $type = $mime[$ext]
  if (-not $type) { $type = "application/octet-stream" }
  $data = [IO.File]::ReadAllBytes($full)
  $ctx.Response.ContentType = $type
  $ctx.Response.Headers.Add("Cache-Control", "no-cache")
  $ctx.Response.ContentLength64 = $data.Length
  $ctx.Response.OutputStream.Write($data, 0, $data.Length)
  $ctx.Response.Close()
  } catch {
    try {
      $ctx.Response.StatusCode = 500
      $errBytes = [Text.Encoding]::ASCII.GetBytes("Internal Server Error")
      $ctx.Response.OutputStream.Write($errBytes, 0, $errBytes.Length)
      $ctx.Response.Close()
    } catch { }
  }
}
