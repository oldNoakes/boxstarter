function Test-BoxstarterPackage {
    [CmdletBinding()]
    param(
        [string[]]$PackageName,
        [switch]$IncludeOutput
    )
    $options = Get-BoxstarterDeployOptions
    if(!$options.DeploymentTargetCredentials){
        throw "No DeploymentTargetCredentials has been sent. Use Set-BoxstarterBuildOptions to set DeploymentTargetCredentials"
    }

    if($options.DeploymentVMProvider -and $options.DeploymentVMProvider -gt 0){
        $vmArgs=@{}
        $cloudVMStates = @{}
        if($options.DeploymentCloudServiceName){$vmArgs.CloudServiceName=$options.DeploymentCloudServiceName}
        if($options.RestoreCheckpoint){$vmArgs.CheckpointName=$options.RestoreCheckpoint}
        $vmArgs.Provider=$options.DeploymentVMProvider
        if($options.DeploymentVMProvider -eq "azure") {
            Write-BoxStarterMessage "Using Azure VMs. Checking to see if these are shutdown..." -verbose
            $options.DeploymentTargetNames | % {
                $thisState = Test-VMStarted $options.DeploymentCloudServiceName $_
                Write-BoxStarterMessage "Is $_ on: $thisState" -verbose
                $cloudVMStates.$_ = $thisState
            }
        }
    }

    $summary=@{
        Passed=0
        Skipped=0
        Failed=0
    }

    $currentColor = $Host.UI.RawUI.ForegroundColor
    $summaryColor = "Green"
    Update-FormatData  -PrependPath "$($Boxstarter.BaseDir)\Boxstarter.CI\TestResult.Format.ps1xml"
    $CurrentVerbosity=$global:VerbosePreference

    try {
        if($PSBoundParameters["Verbose"] -eq $true) {
            $global:VerbosePreference="Continue"
        }

        Get-BoxstarterPackages -PackageName $PackageName | % {
            $Host.UI.RawUI.ForegroundColor = $currentColor
            $pkg = $_
            if($PackageName -or (Test-PackageVersionGreaterThanPublished $pkg)) {
                Invoke-BuildAndTest $pkg.Id $options $vmArgs $IncludeOutput | % {
                    if($_.Status -eq "PASSED") {
                        $summary.Passed++
                        $Host.UI.RawUI.ForegroundColor = "Green"
                    }
                    else {
                        $summary.Failed++
                        $Host.UI.RawUI.ForegroundColor = "Red"
                        $summaryColor= "Red"
                    }
                    Write-Result $pkg $_
                }
                if(!$failed) {$publishCandidates += $pkg.Id}
            }
            else {
                $summary.Skipped++
                Write-Result $pkg
            }
        }
    }
    finally{
        $Host.UI.RawUI.ForegroundColor = $currentColor
        $global:VerbosePreference=$CurrentVerbosity

        $cloudVMStates.Keys | ? { $cloudVMStates.$_ -eq $false -and (Test-VMStarted $options.DeploymentCloudServiceName $_)} | % {
            Write-BoxStarterMessage "Stopping $_..."
            Stop-AzureVM  -ServiceName $options.DeploymentCloudServiceName -Name $_ -Force | Out-Null 
        }
    }

    Write-BoxstarterMessage "Total: $($summary.Passed + $summary.Failed + $summary.Skipped) Passed: $($summary.Passed) Failed: $($summary.Failed) Skipped: $($summary.Skipped)" -Color $summaryColor
}

function Write-Result($package, $result) {
    $res = New-Object PSObject -Property @{
        Package=$package.Id
        RepoVersion=$package.Version
        PublishedVersion=$(if($package.PublishedVersion -eq $null) {"Not Published"} else { $package.PublishedVersion })
        Computer=$result.TestComputerName
        ResultDetails=$(if($result -eq $null) {@{}} else { $result.ResultDetails })
        Status=$(if($result -eq $null) {"SKIPPED"} else { $result.Status })
    }
    $res.PSObject.TypeNames.Insert(0,'BoxstarterTestResult')
    $res | Out-BoxstarterLog -quiet
    return $res
}

function Test-PackageVersionGreaterThanPublished ($package) {
    if(!$package.Feed) { 
        Write-BoxstarterMessage "No feed has been assigned to $($package.Name). It will not be built and tested" -verbose
        return $false 
    }

    if(!$package.PublishedVersion) {
        Write-BoxstarterMessage "$($package.Name) has not yet been published. It will be built and tested" -verbose
        return $true 
    }

    try {
        $pkgVersion=New-Object -TypeName Version -ArgumentList (Remove-PreRelease $package.Version)
    }
    catch [System.Management.Automation.MethodInvocationException] {
        Write-Error "cannot parse version from $(Remove-PreRelease $package.Version)" -Category InvalidOperation
    }
    $pubVersion=New-Object -TypeName Version -ArgumentList (Remove-PreRelease $package.PublishedVersion)

    if($pkgVersion -gt $pubVersion) {
        Write-BoxstarterMessage "The repository version '$($package.Version)' for $($package.Name) is greater than the published version '$($package.PublishedVersion)'. It will be built and tested" -verbose
        return $true 
    }
    else {
        Write-BoxstarterMessage "The repository version '$($package.Version)' for $($package.Name) is not greater than the published version '$($package.PublishedVersion)'. It will not be built and tested" -verbose
        return $false 
    }
}

function Remove-PreRelease ([string]$versionString) {
    $idx=$versionString.IndexOf("-")
    if($idx -gt -1) {
        return $versionString.Substring(0,$idx)
    }
    else {
        return $versionString 
    }
}

function Invoke-BuildAndTest($packageName, $options, $vmArgs, $IncludeOutput) {
    $origLogSetting=$Boxstarter.SuppressLogging
    if($global:VerbosePreference -eq "Continue") {
        Write-BoxstarterMessage "Verbosity is on" -verbose
        $verbose = $true 
    }
    else {
        Write-BoxstarterMessage "Verbosity is off" -verbose
        $verbose = $false 
    }
    if(!$IncludeOutput -and !$verbose){ 
        $Boxstarter.SuppressLogging=$true 
    }
    $progressId=5000 #must be a unique int. This is likely not to conflict with anyone else
    try {
        Write-Progress -id $progressId "Building $packageName."
        Invoke-BoxstarterBuild $packageName -Quiet

        $options.DeploymentTargetNames | % {
            $target=$_
            $global:Boxstarter.ProgressArgs=@{Id=$progressId;Activity="Testing $packageName";Status="on Machine: $target"}
            $a=$global:Boxstarter.ProgressArgs
            Write-Progress @a
            $boxstarterConn=$null
            $result=$null
            try {
                if($vmArgs) {
                    $vmArgs.Keys | % {
                        Write-BoxstarterMessage "vm arg key: $_ has value $($vmArgs[$_])" -Verbose
                    }
                    Write-BoxstarterMessage "connecting to $target using credential username $($options.DeploymentTargetCredentials.UserName)" -Verbose
                    $boxstarterConn = Enable-BoxstarterVM -Credential $options.DeploymentTargetCredentials -VMName $target  @vmArgs -Verbose:$verbose
                }
                else {
                    $boxstarterConn = $target
                }
                $result = $boxstarterConn | Install-BoxstarterPackage -credential $options.DeploymentTargetCredentials -PackageName $packageName -Force -verbose:$verbose
            }
            catch {
                $result = $_
            }
            if(Test-InstallSuccess $result) {
                $status="PASSED"
            }
            else {
                $status="FAILED"
            }
            new-Object PSObject -Property @{
                Package=$packageName 
                TestComputerName=$target
                ResultDetails=$result
                Status=$status
            }
        }
    }finally { 
        $Boxstarter.SuppressLogging = $origLogSetting
        $global:Boxstarter.Remove("ProgressArgs")
    }
}

function Test-InstallSuccess ($testResult) {
    if($testResult.Completed -and ($testResult.Errors.Count -eq 0)) {
        return $true
    }
    return $false
}