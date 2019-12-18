Try {
    [string]$appNameRegEx = '^Application Name' ## Set this value to the application name. Regular expressions can be used.
    [string]$appVersion = '1.0.0.0' ## Set this value to the minimum version to be considered as "installed".
    [string]$appVendorRegEx = 'Vendor Name' ## Set this value to the vendor name. Regular expressions can be used.
    
    ## Nothing should need to be modified below this line

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
    
    ## Registry keys for system wide native and WOW64 applications
    [string[]]$regKeyBranches = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    
    ## Registry key for per user applications
    if (-not(([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem)) {
        ## Detection is running in user context
        $regKeyBranches += Join-Path -Path "HKCU:\" -ChildPath "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    } else {
        ## Detection is running in System context

        ## Looking for user profile hives loaded in HKEY_USERS
        if (-not(Get-PSDrive -Name 'HKU' -ErrorAction SilentlyContinue)) {
            $null = New-PSDrive -Name 'HKU' -PSProvider Registry -Root HKEY_USERS
        }
        $UserSIDs = (Get-ChildItem -Path HKU:).Name -replace '^HKEY_USERS\\',$null | Where-Object -FilterScript {$_ -match '^S\-1\-5\-21\-\d+\-\d+\-\d+\-\d+$'}
        
        ## Checking to see if more than one user profile is loaded
        if (($UserSIDs | Measure-Object | Select-Object -ExpandProperty Count) -gt 1) {
            ## Attemting to determine the active user to limit the search to that user only

            ## Win32_ComputerSystem will return the user logged onto the console -- https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem
            [string]$ConsoleUser = (Get-CimInstance Win32_ComputerSystem).UserName
            if ($ConsoleUser) {
                $UserDomain = $ConsoleUser.Split('\')[0]
                $UserName = $ConsoleUser.Split('\')[1]
                $UserObject = New-Object System.Security.Principal.NTAccount("$Domain","$UserName")
                $UserSID = ($UserObject.Translate([System.Security.Principal.SecurityIdentifier])).Value
            } else {
                ## Using Win32_LogonSession to look for a LogonType of "10" (Terminal Services session that is both remote and interactive) and using the most recent logon if found -- https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logonsession
                [string]$LogonId = Get-CimInstance Win32_LogonSession | Where-Object -FilterScript {$_.LogonType -eq '10'} | Sort-Object -Property StartTime -Descending | Select-Object -First 1 -ExpandProperty LogonId
                $ActiveSession = Get-CimInstance Win32_LoggedOnUser | Where-Object -FilterScript {$_.Dependent.LogonId -eq $LogonId}
                if ($ActiveSession) {
                    $UserDomain = $ActiveSession.Antecedent.Domain
                    $UserName = $ActiveSession.Antecedent.Name
                    $UserObject = New-Object System.Security.Principal.NTAccount("$Domain","$UserName")
                    $UserSID = ($UserObject.Translate([System.Security.Principal.SecurityIdentifier])).Value
                }
            }
            if (($UserSID) -and ($UserSIDs | Where-Object -FilterScript {$_ -eq "$UserSID"})) {
                ## Removing all SIDs except for the active to make user based detection more accurate
                $UserSIDs = $UserSIDs | Where-Object -FilterScript {$_ -eq "$UserSID"}
            }
        }
        
        foreach ($SID in $UserSIDs) {
            [string[]]$regKeyBranches += Join-Path -Path "HKU:\" -ChildPath "$SID\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        }
    }

    ## Searching the installed applications from the registry for applications that have the "DisplayName" and "Publisher" property
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
                            Write-Output ($regKeyProperties.Publisher)
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