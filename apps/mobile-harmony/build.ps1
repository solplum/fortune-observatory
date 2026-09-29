# Build script for the destiny HarmonyOS app (invoked by build.cmd).
# Keep this file ASCII-only: PowerShell 5.1 reads BOM-less .ps1 files in the ANSI
# codepage, and Chinese comments garble into broken tokens that can swallow lines.
# Sets env vars -> ohpm install -> hvigor build; full log to build-last.log;
# stdout echoes only the last ~100 lines and ends with BUILD_EXIT=<code>.
param([string]$Task = 'assembleHap')

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$deveco = 'D:\Huawei\DevEcoStudio'
$log = Join-Path $here 'build-last.log'

if ([string]::IsNullOrWhiteSpace($Task)) {
  $Task = 'assembleHap'
}

# --- environment ---
# DevEco single-dir SDK layout (contains the 'default' folder); DEVECO_SDK_HOME -> sdk root
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:HOS_SDK_HOME = $env:DEVECO_SDK_HOME
# hvigorw.bat resolves node via NODE_HOME or PATH; ohpm.bat likewise
$env:NODE_HOME = Join-Path $deveco 'tools\node'
$env:JAVA_HOME = Join-Path $deveco 'jbr'
$env:PATH = "$env:NODE_HOME;" + (Join-Path $deveco 'tools\ohpm\bin') + ';' + (Join-Path $deveco 'tools\hvigor\bin') + ';' + $env:PATH

Set-Content -Path $log -Value ("=== destiny mobile-harmony build | task=$Task | " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===") -Encoding UTF8

function Write-Step([string]$msg) {
  $line = "[build.ps1] $msg"
  Add-Content -Path $log -Value $line -Encoding UTF8
  Write-Host $line
}

function Invoke-Step {
  param([string]$Title, [string]$FilePath, [string]$ArgLine)
  Write-Step $Title
  if ([string]::IsNullOrWhiteSpace($ArgLine)) {
    Add-Content -Path $log -Value "[build.ps1] empty argument line for $FilePath" -Encoding UTF8
    return 1
  }
  $outTmp = Join-Path $env:TEMP ("destiny_build_out_" + [guid]::NewGuid().ToString('N') + ".log")
  $errTmp = Join-Path $env:TEMP ("destiny_build_err_" + [guid]::NewGuid().ToString('N') + ".log")
  $p = Start-Process -FilePath $FilePath -ArgumentList $ArgLine -WorkingDirectory $here `
    -RedirectStandardOutput $outTmp -RedirectStandardError $errTmp -NoNewWindow -PassThru -Wait
  $o = Get-Content -Path $outTmp -Encoding UTF8 -ErrorAction SilentlyContinue
  $e = Get-Content -Path $errTmp -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($o) { Add-Content -Path $log -Value $o -Encoding UTF8 }
  if ($e) { Add-Content -Path $log -Value $e -Encoding UTF8 }
  Remove-Item $outTmp, $errTmp -ErrorAction SilentlyContinue
  if ($null -eq $p) {
    return 1
  }
  return $p.ExitCode
}

$ohpm = Join-Path $deveco 'tools\ohpm\bin\ohpm.bat'
$hvigorw = Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat'

if (-not (Test-Path $ohpm)) {
  Add-Content -Path $log -Value "[build.ps1] ohpm not found: $ohpm" -Encoding UTF8
  $code = 1
}
elseif (-not (Test-Path $hvigorw)) {
  Add-Content -Path $log -Value "[build.ps1] hvigorw not found: $hvigorw" -Encoding UTF8
  $code = 1
}
else {
  # Step 1: install dependencies (zero third-party deps; idempotent and fast)
  $code = Invoke-Step 'step 1/2: ohpm install' -FilePath $ohpm -ArgLine 'install'
  if ($code -ne 0) {
    Add-Content -Path $log -Value "[build.ps1] ohpm install failed with exit code $code" -Encoding UTF8
  }
  else {
    # Step 2: hvigor build (debug, unsigned HAP)
    $argLine = "--mode module -p module=entry@default -p product=default -p buildMode=debug $Task --no-daemon"
    $code = Invoke-Step "step 2/2: hvigor $Task" -FilePath $hvigorw -ArgLine $argLine
  }
}

if ($null -eq $code) {
  $code = 1
}
Add-Content -Path $log -Value ("[build.ps1] finished with exit code $code") -Encoding UTF8

# stdout echoes the last ~100 lines + BUILD_EXIT
$tail = Get-Content -Path $log -Tail 100 -ErrorAction SilentlyContinue
if ($tail) {
  $tail | ForEach-Object { Write-Host $_ }
}
Write-Host "BUILD_EXIT=$code"
exit $code
