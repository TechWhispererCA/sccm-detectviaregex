Try {
    [string]$appNameRegEx = '^Application Name'
    [string]$appVersion = '1.0.0.0'
    [string]$appVendorRegEx = 'Vendor'
    
    # Nothing should need to be modified below this line

    function Compare-Versions {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [string]$DeploymentVersion,
            [Parameter(Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [string]$DetectedVersion
        )
        Try {
            # Attempting to use the [version] type
            [version]$vDeploymentVersion = $DeploymentVersion
            [version]$vDetectedVersion = $DetectedVersion
            if ($vDetectedVersion -ge $vDeploymentVersion) {
                Return $true
            } else {
                Return $false
            }
        } Catch {
            if (($DetectedVersion -notmatch '\D') -and ($DeploymentVersion -notmatch '\D')) {
                # Both versions contain only numbers
                Try {
                    [int32]$intDetectedVersion = $DetectedVersion
                    [int32]$intDeploymentVersion = $DeploymentVersion
                    if ($intDetectedVersion -ge $intDeploymentVersion) {
                        Return $true
                    } else {
                        Return $false
                    }
                } Catch {
                    # Failing back to comparing as strings
                }
            }     
            if ($DetectedVersion -ge $DeploymentVersion) {
                Return $true
            } else {
                Return $false
            }
        }
    }
    
    [string[]]$regKeyBranches = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    :Search foreach ($regKeyBranch in $regKeyBranches) {
        If (Test-Path -LiteralPath $regKeyBranch -ErrorAction 'SilentlyContinue') {
            [psobject[]]$UninstallKeys = Get-ChildItem -Path $regKeyBranch -Recurse
            foreach ($UninstallKey in $UninstallKeys) {
                $regKey = ($UninstallKey.PSChildName)
                Try {$regKeyProperties = Get-ItemProperty -LiteralPath "$regKeyBranch\$regKey" -ErrorAction Stop}
                Catch {Continue}
                if ((($regKeyProperties.DisplayName) -match $appNameRegEx) -and (($regKeyProperties.Publisher) -match $appVendorRegEx)) {
                    Try {
                        if (($appVersion) -and (($regKeyProperties).DisplayVersion) -and (Compare-Versions -DeploymentVersion $appVersion -DetectedVersion (($regKeyProperties).DisplayVersion))) {
                            Write-Output ($regKeyProperties.DisplayName)
                            Write-Output ($regKeyProperties.DisplayVersion)
                            Break Search
                        }           
                    } Catch {
                        Continue
                    }
                }
            }
        }
    }

    Exit 0

} Catch {
    Exit 60001
}