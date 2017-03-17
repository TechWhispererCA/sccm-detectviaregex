Try {
    [string]$appNameRegEx = '^Cisco AnyConnect.*'
    [string]$appVersion = '3.1.10010'
    [bool]$matchFound = $false
    [string[]]$regKeyBranches = 'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    :Search foreach ($regKeyBranch in $regKeyBranches) {
        If (Test-Path -LiteralPath $regKeyBranch -ErrorAction 'SilentlyContinue') {
            [psobject[]]$UninstallKeys = Get-ChildItem -Path $regKeyBranch -Recurse
            foreach ($UninstallKey in $UninstallKeys) {
                $regKey = ($UninstallKey.PSChildName)
                Try {$regKeyProperties = Get-ItemProperty -LiteralPath "$regKeyBranch\$regKey" -ErrorAction Stop}
                Catch {Continue}
                if (($regKeyProperties.DisplayName) -match $appNameRegEx) {
                    switch -Regex ($appVersion) {
                        '^\d\..*' {
                            if (($regKeyProperties.DisplayVersion -match '\d\..*') -and (($regKeyProperties.DisplayVersion) -ge $appVersion)) {
                                [bool]$matchFound = $true
                                Break
                            } elseif (($regKeyProperties.DisplayVersion) -match '\d{2,}\..*') {
                                [bool]$matchFound = $true
                                Break
                            }
                        }
                        '^\d{2}\..*' {
                            if (($regKeyProperties.DisplayVersion) -match '\d\..*') {
                                [bool]$matchFound = $true
                                Break
                            } elseif (($regKeyProperties.DisplayVersion) -match '\d{3,}\..*') {
                                [bool]$matchFound = $true
                                Break
                            } elseif (($regKeyProperties.DisplayVersion) -ge $appVersion) {
                                [bool]$matchFound = $true
                                Break
                            }
                        }
                        '^\d{3}\..*' {
                            if (($regKeyProperties.DisplayVersion) -match '\d{1,2}\..*') {
                                [bool]$matchFound = $true
                                Break
                            } elseif (($regKeyProperties.DisplayVersion) -ge $appVersion) {
                                [bool]$matchFound = $true
                                Break
                            }
                        }
                        default {Throw 'Check version number.'}
                    }

                    if ($matchFound) {
                        Write-Output ($regKeyProperties.DisplayName)
                        Write-Output ($regKeyProperties.DisplayVersion)
                        Break Search
                    }             
                }
            }
        }
    }
} Catch {
    Exit 60001
}