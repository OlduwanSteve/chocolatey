﻿function Chocolatey-List {
param(
  [string] $selector='',
  [string] $source='',
  [switch] $returnOutput = $false
)
  Write-Debug "Running 'Chocolatey-List' with selector: `'$selector`', source:`'$source`'";

  if ($source -like 'webpi') {
    $chocoInstallLog = Join-Path $nugetChocolateyPath 'chocolateyWebPIList.log';
    $webpiArgs ="/c webpicmd /List /ListOption:All"
    Start-ChocolateyProcessAsAdmin "cmd.exe $webpiArgs | Tee-Object -FilePath `'$chocoInstallLog`';" -nosleep
    Create-InstallLogIfNotExists $chocoInstallLog
    $installOutput = Get-Content $chocoInstallLog -Encoding Ascii
    foreach ($line in $installOutput) {
      Write-Host $line
    }
  } elseif ($source -like 'windowsfeatures') {
    $chocoInstallLog = Join-Path $nugetChocolateyPath 'chocolateyWindowsFeaturesInstall.log';
    Append-Log $chocoInstallLog
    $windowsFeaturesArgs ="/c dism /online /get-features /format:table | Tee-Object -FilePath `'$chocoInstallLog`';"
    Start-ChocolateyProcessAsAdmin "cmd.exe $windowsFeaturesArgs" -nosleep
    Create-InstallLogIfNotExists $chocoInstallLog
    $installOutput = Get-Content $chocoInstallLog -Encoding Ascii
    
    $skippedHeader = $false
    $skippedDashes = $false
    foreach ($line in $installOutput) {
      if (!$skippedHeader){
        $skippedHeader = $line.StartsWith('Feature Name')
        continue
      }
      if (!$skippedDashes){
        $skippedDashes = $line.StartsWith('-------')
        continue
      }
      if ($line.Length -eq 0){
        continue
      }
      $parts = $line.split('|')
      if ($parts.Length -lt 2){
        continue
      }
      $featureName = $parts[0].Trim()
      $featureStatus = $parts[1]
      
      if (!$localOnly -or $featureStatus.Contains('Enabled')){
        Write-Host "$featureName 1"
      }
    }
  } else {
    $params = @()
    $params += 'list'
    $parameters = "list"
    if ($selector -ne '') {
      $params += "`"$selector`""
    }

    if ($allVersions -eq $true) {
      Write-Debug "Showing all versions of packages"
      $params += '-all'
    }

    if ($prerelease -eq $true -or $localonly) {
      Write-Debug "Showing prerelease versions of packages"
      $params += '-Prerelease'
    }

    if ($verbosity -eq $true) {
      $params += '-verbosity', 'detailed'
    }
    $params += '-NonInteractive'

    if ($localonly) {
      $source = $nugetLibPath
    }

    if ($source -ne '') {
      $params += '-Source', "`"$source`""
    } else {
      $srcArgs = Get-SourceArguments $source
      if ($srcArgs -ne '') {
        $srcArgs = $srcArgs.Replace('-Source ','')
        $params += '-Source', "$srcArgs" #already quoted from Get-SourceArguments
      }
    }

    Write-Debug "Executing command [`"$nugetExe`" $params]"
    $global:packageList = @{}

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo($nugetExe, $params)
    if ($returnOutput) {
      $LogAction = {
        # we know this is one line of data otherwise we would need to split lines
        foreach ($line in $EventArgs.Data) {
         # Write-Host "$line" #this line really slows things down
          if (!$line.IsNullOrEmpty) {
            $package = $line.Split(" ")
            $global:packageList.Add("$($package[0])","$($package[1])")
          }
        }
      }
      $writeOutput = $LogAction
      $writeError = $LogAction

      $process.EnableRaisingEvents = $true
      Register-ObjectEvent  -InputObject $process -EventName OutputDataReceived -Action $writeOutput | Out-Null
      Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action  $writeError | Out-Null

      # Redirecting output slows things down a bit. In
      # the interest of performance, only use redirection
      # if we are returning a PS-Object at the end
      $process.StartInfo.RedirectStandardOutput = $true
      $process.StartInfo.RedirectStandardError = $true
    }
    $process.StartInfo.UseShellExecute = $false

    $process.Start() | Out-Null
    if ($process.StartInfo.RedirectStandardOutput) { $process.BeginOutputReadLine() }
    if ($process.StartInfo.RedirectStandardError) { $process.BeginErrorReadLine() }
    $process.WaitForExit()

    Write-Debug "Command [`"$nugetExe`" $params] exited with `'$($process.ExitCode)`'."

    if ($returnOutput) {
      return $packageList
    }
  }
}
