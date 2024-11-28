function Install-WinUtilWinget {
    <#

    .SYNOPSIS
        Installs/updates Winget.

    .DESCRIPTION
        This function will download the latest version of Winget and install it. If Winget is already installed, it will do nothing.

    #>

    # Check if Windows supports Winget
    if ((Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber -lt 17763) {
        Write-Host "Winget is not supported on this version of Windows (Pre-1809)" -Fore Red
        return
    }

    # Check if Winget is installed
    switch (Test-WinUtilPackageManager -Winget) {
        installed   { Write-Host "`nWinget is already installed.`r" -Fore Green; return }
        outdated    { Write-Host "`nWinget is outdated. Continuing with install.`r" -Fore Yellow }
        default     { Write-Host "`nWinget is not installed. Continuing with install.`r" -Fore Red }
    }

    # Supress progress bar to prioritize download speed
    $progressPreference = 'SilentlyContinue'

    try {
        # Download required dependencies
        Write-Host "Downloading dependencies"
        $dependenciesUrl = 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip'
        $dependenciesZip = Join-Path (Get-Item $env:TEMP).FullName (Split-Path $dependenciesUrl -Leaf)
        Invoke-WebRequest -Uri $dependenciesUrl -Outfile $dependenciesZip

        # Extracting dependencies
        $extractedDependencies = Join-Path (Get-Item $dependenciesZip).DirectoryName (Get-Item $dependenciesZip).BaseName
        Expand-Archive $dependenciesZip -DestinationPath $extractedDependencies -Force

        $architecture = [System.Runtime.InteropServices.RuntimeInformation,mscorlib]::OSArchitecture.ToString().ToLower()

        # Get Winget dependency info from GitHub
        Write-Host "Checking Winget dependencies"
        $versionsUrl = 'https://github.com/microsoft/winget-cli/releases/download/v1.9.25200/DesktopAppInstaller_Dependencies.json'
        $dependencyFiles = Invoke-WebRequest -Uri $versionsUrl | ConvertFrom-Json | Select -Expand Dependencies | ForEach {
            Get-ChildItem $extractedDependencies\$architecture\$_*.appx
        }

        # Download license file
        Write-Host "Downloading license file"
        $apiUrl = 'https://api.github.com/repos/microsoft/Winget-cli/releases/latest'
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
        $latestVersion = $response.tag_name
        $licenseUrl = $response.assets.browser_download_url | Where-Object {$_ -like "*License1.xml"} # Index value for License file.
        $licenseFile = Join-Path (Get-Item $env:TEMP).FullName (Split-Path $licenseUrl -Leaf)
        Invoke-WebRequest -Uri $licenseUrl -OutFile $licenseFile

        # Download Winget
        Write-Host "Downloading Winget $latestVersion"
        $wingetUrl = 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $wingetFile = Join-Path (Get-Item $env:TEMP).FullName (Split-Path $wingetUrl -Leaf)
        Invoke-WebRequest -Uri $wingetUrl -Outfile $wingetFile

        # Install Winget
        Write-Host "Installing Winget w/ dependencies"
        Add-AppxProvisionedPackage -Online -PackagePath $wingetFile -DependencyPackagePath $dependencyFiles -LicensePath $licenseFile

        Write-Host "Adding Winget Source from Winget CDN"
        Add-AppxPackage -Path https://cdn.winget.microsoft.com/cache/source.msix # Seems some installs of Winget don't add the repo source, this should makes sure that it's installed every time.
        Write-Host "Winget Installed" -Fore Green

        Write-Host "Enabling NuGet and Winget Module"
        Install-PackageProvider -Name NuGet -Force
        Install-Module -Name Microsoft.WinGet.Client -Force

        Write-Output "Refreshing Environment Variables`n"
        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } catch {
        Write-Host "Winget install failed w/ GitHub method" -Fore Red
        Write-Host "- Error : $error" -Fore Red

        try {
            Write-Host "Installing Winget w/ Chocolatey"
            Install-WinUtilChoco # Install Choco if not already present
            Start-Process -Verb runas -FilePath powershell.exe -ArgumentList "choco install winget-cli"
            Write-Host "Winget Installed" -ForegroundColor Green
            Write-Output "Refreshing Environment Variables...`n"
            $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } catch {
            throw [WingetFailedInstall]::new('Failed to install!')
        }
    } finally {
        # Remove downloaded files
        $dependenciesZip, $extractedDependencies, $licenseFile, $wingetFile | ForEach {
            if (Test-Path $_) {
                Remove-Item $_ -Force -Recurse
            }
        }
    }
}
