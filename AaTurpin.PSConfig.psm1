function Read-SettingsFile {
    <#
    .SYNOPSIS
        Reads and parses the settings.json configuration file with validation.
    
    .DESCRIPTION
        This cmdlet reads the settings.json file, parses the JSON content, validates
        drive mappings and monitored directories, and returns a PowerShell object
        containing the configuration settings. If the settings file doesn't exist,
        it will be created automatically using New-SettingsFile.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $config = Read-SettingsFile -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        $config = Read-SettingsFile -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the validated settings configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Reading settings from: $SettingsPath"
    
    try {
        # Check if file exists, create if not
        if (-not (Test-Path -Path $SettingsPath -PathType Leaf)) {
            Write-LogInfo -LogPath $LogPath -Message "Settings file not found, creating new file: $SettingsPath"
            New-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        }
        
        # Read and parse JSON
        $jsonContent = Get-Content -Path $SettingsPath -Raw -ErrorAction Stop
        $settings = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        # Set default staging area if missing
        if (-not $settings.PSObject.Properties.Name -contains "stagingArea" -or 
            [string]::IsNullOrWhiteSpace($settings.stagingArea)) {
            $settings | Add-Member -MemberType NoteProperty -Name "stagingArea" -Value "C:\StagingArea" -Force
            Write-LogWarning -LogPath $LogPath -Message "Using default staging area: C:\StagingArea"
        }
        
        # Initialize driveMappings if missing
        if (-not ($settings.PSObject.Properties.Name -contains "driveMappings")) {
            $settings | Add-Member -MemberType NoteProperty -Name "driveMappings" -Value @() -Force
        }
        
        # Initialize monitoredDirectories if missing
        if (-not ($settings.PSObject.Properties.Name -contains "monitoredDirectories")) {
            $settings | Add-Member -MemberType NoteProperty -Name "monitoredDirectories" -Value @() -Force
        }
        
        # Validate drive mappings
        $validDriveMappings = @()
        if ($settings.driveMappings -and $settings.driveMappings.Count -gt 0) {
            foreach ($mapping in $settings.driveMappings) {
                if (Test-DriveMapping -Mapping $mapping -LogPath $LogPath) {
                    $validDriveMappings += $mapping
                }
            }
        }
        $settings.driveMappings = $validDriveMappings
        
        # Validate monitored directories
        $validMonitoredDirs = @()
        if ($settings.monitoredDirectories -and $settings.monitoredDirectories.Count -gt 0) {
            foreach ($dir in $settings.monitoredDirectories) {
                if (Test-MonitoredDirectory -Directory $dir -LogPath $LogPath) {
                    $validMonitoredDirs += $dir
                }
            }
        }
        $settings.monitoredDirectories = $validMonitoredDirs
        
        Write-LogInfo -LogPath $LogPath -Message "Configuration loaded: $($validDriveMappings.Count) drive mappings, $($validMonitoredDirs.Count) monitored directories"
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to read settings file" -Exception $_.Exception
        throw
    }
}

function New-SettingsFile {
    <#
    .SYNOPSIS
        Creates a new settings.json configuration file with default values and returns the settings object.
    
    .DESCRIPTION
        This cmdlet creates a new settings.json file with default configuration values.
        The file will contain a default staging area path and empty arrays for drive
        mappings and monitored directories. If the file already exists, it will be overwritten.
        Returns the created settings object for immediate use.
    
    .PARAMETER SettingsPath
        The path where the settings.json file will be created. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .PARAMETER StagingArea
        The staging area path to use. Defaults to "C:\StagingArea".
    
    .EXAMPLE
        $settings = New-SettingsFile -LogPath "C:\Logs\app.log"
        Creates a new settings.json file in the current directory with default values and returns the settings object.
    
    .EXAMPLE
        $config = New-SettingsFile -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Creates a new settings.json file at the specified path, overwriting if it exists, and returns the settings.
    
    .EXAMPLE
        $settings = New-SettingsFile -LogPath "C:\Logs\app.log" -StagingArea "D:\MyStaging"
        Creates a new settings.json file with a custom staging area path and returns the settings object.
    
    .OUTPUTS
        PSCustomObject containing the created settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$StagingArea = "C:\StagingArea"
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Creating new settings file: $SettingsPath"
    
    try {
        # Check if file already exists
        if (Test-Path -Path $SettingsPath -PathType Leaf) {
            Write-LogWarning -LogPath $LogPath -Message "Overwriting existing settings file: $SettingsPath"
        }
        
        # Create default settings object
        $defaultSettings = [PSCustomObject]@{
            stagingArea = $StagingArea
            driveMappings = @()
            monitoredDirectories = @()
        }
        
        # Convert to JSON with proper formatting
        $jsonContent = $defaultSettings | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Ensure directory exists
        $settingsDir = Split-Path -Path $SettingsPath -Parent
        if ($settingsDir -and -not (Test-Path -Path $settingsDir -PathType Container)) {
            Write-LogInfo -LogPath $LogPath -Message "Creating directory: $settingsDir"
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }
        
        # Write the file
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Create settings file")) {
            Set-Content -Path $SettingsPath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
            Write-LogInfo -LogPath $LogPath -Message "Successfully created settings file: $SettingsPath"
            Write-LogDebug -LogPath $LogPath -Message "Default staging area: $StagingArea"
        }
        
        # Return the settings object for immediate use
        Write-LogDebug -LogPath $LogPath -Message "Returning created settings object"
        return $defaultSettings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to create settings file" -Exception $_.Exception
        throw
    }
}

function Set-StagingArea {
    <#
    .SYNOPSIS
        Sets the staging area path in the configuration file.
    
    .DESCRIPTION
        This cmdlet updates the stagingArea property in the settings.json file with a new path.
        The settings file is read, modified, and written back to disk.
    
    .PARAMETER StagingAreaPath
        The new staging area path to set.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Set-StagingArea -StagingAreaPath "D:\NewStaging" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Set-StagingArea -StagingAreaPath "E:\Temp\Staging" -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StagingAreaPath,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Setting staging area to: $StagingAreaPath"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Update staging area
        $oldStagingArea = $settings.stagingArea
        $settings.stagingArea = $StagingAreaPath
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Update staging area from '$oldStagingArea' to '$StagingAreaPath'")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully updated staging area from '$oldStagingArea' to '$StagingAreaPath'"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to set staging area" -Exception $_.Exception
        throw
    }
}

function Add-DriveMapping {
    <#
    .SYNOPSIS
        Adds a new drive mapping to the configuration file.
    
    .DESCRIPTION
        This cmdlet adds a new drive mapping with the specified letter and UNC path to the settings.json file.
        The drive letter must be unique and the UNC path must be valid.
    
    .PARAMETER Letter
        The drive letter for the mapping (single alphabetic character).
    
    .PARAMETER Path
        The UNC path for the drive mapping.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Add-DriveMapping -Letter "X" -Path "\\server\share" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Add-DriveMapping -Letter "Y" -Path "\\nas\data" -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateLength(1, 1)]
        [ValidateScript({[char]::IsLetter($_)})]
        [string]$Letter,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({$_.StartsWith("\\") -and $_.Length -gt 2})]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    $Letter = $Letter.ToUpper()
    Write-LogInfo -LogPath $LogPath -Message "Adding drive mapping: $Letter -> $Path"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Check if drive letter already exists
        $existingMapping = $settings.driveMappings | Where-Object { $_.letter -eq $Letter }
        if ($existingMapping) {
            $errorMsg = "Drive letter '$Letter' already exists with path '$($existingMapping.path)'"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Create new mapping
        $newMapping = [PSCustomObject]@{
            letter = $Letter
            path = $Path
        }
        
        # Add to settings
        $settings.driveMappings += $newMapping
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Add drive mapping '$Letter' -> '$Path'")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully added drive mapping: $Letter -> $Path"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to add drive mapping" -Exception $_.Exception
        throw
    }
}

function Remove-DriveMapping {
    <#
    .SYNOPSIS
        Removes a drive mapping from the configuration file.
    
    .DESCRIPTION
        This cmdlet removes the drive mapping with the specified letter from the settings.json file.
    
    .PARAMETER Letter
        The drive letter of the mapping to remove.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Remove-DriveMapping -Letter "X" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Remove-DriveMapping -Letter "Y" -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateLength(1, 1)]
        [ValidateScript({[char]::IsLetter($_)})]
        [string]$Letter,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    $Letter = $Letter.ToUpper()
    Write-LogInfo -LogPath $LogPath -Message "Removing drive mapping: $Letter"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Find existing mapping
        $existingMapping = $settings.driveMappings | Where-Object { $_.letter -eq $Letter }
        if (-not $existingMapping) {
            $errorMsg = "Drive letter '$Letter' not found in configuration"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Remove mapping
        $settings.driveMappings = $settings.driveMappings | Where-Object { $_.letter -ne $Letter }
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Remove drive mapping '$Letter' -> '$($existingMapping.path)'")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully removed drive mapping: $Letter -> $($existingMapping.path)"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to remove drive mapping" -Exception $_.Exception
        throw
    }
}

function Set-DriveMapping {
    <#
    .SYNOPSIS
        Modifies an existing drive mapping in the configuration file.
    
    .DESCRIPTION
        This cmdlet updates the UNC path for an existing drive mapping identified by its letter.
    
    .PARAMETER Letter
        The drive letter of the mapping to modify.
    
    .PARAMETER Path
        The new UNC path for the drive mapping.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Set-DriveMapping -Letter "X" -Path "\\newserver\share" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Set-DriveMapping -Letter "Y" -Path "\\nas\newdata" -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateLength(1, 1)]
        [ValidateScript({[char]::IsLetter($_)})]
        [string]$Letter,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({$_.StartsWith("\\") -and $_.Length -gt 2})]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    $Letter = $Letter.ToUpper()
    Write-LogInfo -LogPath $LogPath -Message "Modifying drive mapping: $Letter -> $Path"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Find existing mapping
        $existingMapping = $settings.driveMappings | Where-Object { $_.letter -eq $Letter }
        if (-not $existingMapping) {
            $errorMsg = "Drive letter '$Letter' not found in configuration"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        $oldPath = $existingMapping.path
        
        # Update the path
        $existingMapping.path = $Path
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Update drive mapping '$Letter' from '$oldPath' to '$Path'")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully updated drive mapping: $Letter from '$oldPath' to '$Path'"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to modify drive mapping" -Exception $_.Exception
        throw
    }
}

function Add-MonitoredDirectory {
    <#
    .SYNOPSIS
        Adds a new monitored directory to the configuration file.
    
    .DESCRIPTION
        This cmdlet adds a new monitored directory with the specified path and optional exclusions to the settings.json file.
        The path must be unique in the configuration.
    
    .PARAMETER Path
        The path of the directory to monitor.
    
    .PARAMETER Exclusions
        Optional array of subdirectory names to exclude from monitoring.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Add-MonitoredDirectory -Path "C:\MyFolder" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Add-MonitoredDirectory -Path "D:\Data" -Exclusions @("temp", "cache") -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Add-MonitoredDirectory -Path "V:\aeapps\newtools" -Exclusions @("logs") -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Exclusions = @(),
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Adding monitored directory: $Path"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Check if path already exists
        $existingDir = $settings.monitoredDirectories | Where-Object { $_.path -eq $Path }
        if ($existingDir) {
            $errorMsg = "Monitored directory path '$Path' already exists"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Create new monitored directory
        $newDirectory = [PSCustomObject]@{
            path = $Path
            exclusions = $Exclusions
        }
        
        # Add to settings
        $settings.monitoredDirectories += $newDirectory
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Add monitored directory '$Path' with $($Exclusions.Count) exclusions")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully added monitored directory: $Path (exclusions: $($Exclusions.Count))"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to add monitored directory" -Exception $_.Exception
        throw
    }
}

function Remove-MonitoredDirectory {
    <#
    .SYNOPSIS
        Removes a monitored directory from the configuration file.
    
    .DESCRIPTION
        This cmdlet removes the monitored directory with the specified path from the settings.json file.
    
    .PARAMETER Path
        The path of the monitored directory to remove.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Remove-MonitoredDirectory -Path "C:\OldFolder" -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Remove-MonitoredDirectory -Path "V:\aeapps\oldtools" -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Removing monitored directory: $Path"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Find existing directory
        $existingDir = $settings.monitoredDirectories | Where-Object { $_.path -eq $Path }
        if (-not $existingDir) {
            $errorMsg = "Monitored directory path '$Path' not found in configuration"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Remove directory
        $settings.monitoredDirectories = $settings.monitoredDirectories | Where-Object { $_.path -ne $Path }
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Remove monitored directory '$Path'")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully removed monitored directory: $Path"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to remove monitored directory" -Exception $_.Exception
        throw
    }
}

function Set-MonitoredDirectory {
    <#
    .SYNOPSIS
        Modifies an existing monitored directory in the configuration file.
    
    .DESCRIPTION
        This cmdlet updates the exclusions list for an existing monitored directory identified by its path.
    
    .PARAMETER Path
        The path of the monitored directory to modify.
    
    .PARAMETER Exclusions
        The new array of subdirectory names to exclude from monitoring.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        Set-MonitoredDirectory -Path "C:\MyFolder" -Exclusions @("temp", "cache", "logs") -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        Set-MonitoredDirectory -Path "V:\aeapps\tools" -Exclusions @() -LogPath "C:\Logs\app.log"
        # Removes all exclusions for the specified path
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Exclusions,
        
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Modifying monitored directory: $Path"
    
    try {
        # Read current settings
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Find existing directory
        $existingDir = $settings.monitoredDirectories | Where-Object { $_.path -eq $Path }
        if (-not $existingDir) {
            $errorMsg = "Monitored directory path '$Path' not found in configuration"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        $oldExclusionsCount = $existingDir.exclusions.Count
        
        # Update the exclusions
        $existingDir.exclusions = $Exclusions
        
        # Save updated settings
        if ($PSCmdlet.ShouldProcess($SettingsPath, "Update monitored directory '$Path' exclusions from $oldExclusionsCount to $($Exclusions.Count) items")) {
            Save-SettingsFile -Settings $settings -SettingsPath $SettingsPath -LogPath $LogPath
            Write-LogInfo -LogPath $LogPath -Message "Successfully updated monitored directory: $Path (exclusions changed from $oldExclusionsCount to $($Exclusions.Count) items)"
        }
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to modify monitored directory" -Exception $_.Exception
        throw
    }
}

function Save-SettingsFile {
    <#
    .SYNOPSIS
        Saves the settings object to the specified JSON file.
    
    .DESCRIPTION
        This is a helper function that converts the settings object to JSON and writes it to the file.
        Used internally by other configuration management cmdlets.
    
    .PARAMETER Settings
        The settings object to save.
    
    .PARAMETER SettingsPath
        The path to the settings.json file.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings,
        
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    try {
        # Convert to JSON with proper formatting
        $jsonContent = $Settings | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Ensure directory exists
        $settingsDir = Split-Path -Path $SettingsPath -Parent
        if ($settingsDir -and -not (Test-Path -Path $settingsDir -PathType Container)) {
            Write-LogInfo -LogPath $LogPath -Message "Creating directory: $settingsDir"
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }
        
        # Write the file
        Set-Content -Path $SettingsPath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
        Write-LogDebug -LogPath $LogPath -Message "Successfully saved settings to: $SettingsPath"
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to save settings file" -Exception $_.Exception
        throw
    }
}

function Test-DriveMapping {
    <#
    .SYNOPSIS
        Validates a drive mapping object.
    
    .PARAMETER Mapping
        The drive mapping object to validate.
    
    .PARAMETER LogPath
        Path to log file for validation messages.
    
    .OUTPUTS
        Boolean indicating if the mapping is valid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Mapping,
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    try {
        # Check required properties exist
        if (-not ($Mapping.PSObject.Properties.Name -contains "letter" -and 
                  $Mapping.PSObject.Properties.Name -contains "path")) {
            Write-LogWarning -LogPath $LogPath -Message "Drive mapping missing required properties (letter/path)"
            return $false
        }
        
        # Validate letter is single alphabetic character
        if ([string]::IsNullOrWhiteSpace($Mapping.letter) -or 
            $Mapping.letter.Length -ne 1 -or 
            -not [char]::IsLetter($Mapping.letter)) {
            Write-LogWarning -LogPath $LogPath -Message "Invalid drive letter: '$($Mapping.letter)'"
            return $false
        }
        
        # Validate UNC path format
        if ([string]::IsNullOrWhiteSpace($Mapping.path) -or 
            -not $Mapping.path.StartsWith("\\") -or 
            $Mapping.path.Length -le 2) {
            Write-LogWarning -LogPath $LogPath -Message "Invalid UNC path for drive $($Mapping.letter): '$($Mapping.path)'"
            return $false
        }
        
        Write-LogDebug -LogPath $LogPath -Message "Valid drive mapping: $($Mapping.letter) -> $($Mapping.path)"
        return $true
    }
    catch {
        Write-LogWarning -LogPath $LogPath -Message "Error validating drive mapping" -Exception $_.Exception
        return $false
    }
}

function Test-MonitoredDirectory {
    <#
    .SYNOPSIS
        Validates a monitored directory object.
    
    .PARAMETER Directory
        The monitored directory object to validate.
    
    .PARAMETER LogPath
        Path to log file for validation messages.
    
    .OUTPUTS
        Boolean indicating if the directory configuration is valid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Directory,
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    try {
        # Check required path property
        if (-not ($Directory.PSObject.Properties.Name -contains "path") -or 
            [string]::IsNullOrWhiteSpace($Directory.path)) {
            Write-LogWarning -LogPath $LogPath -Message "Monitored directory missing or empty path"
            return $false
        }
        
        # Ensure exclusions property exists and is array
        if (-not ($Directory.PSObject.Properties.Name -contains "exclusions")) {
            $Directory | Add-Member -MemberType NoteProperty -Name "exclusions" -Value @() -Force
        } elseif ($Directory.exclusions -isnot [array]) {
            $Directory.exclusions = @($Directory.exclusions)
        }
        
        Write-LogDebug -LogPath $LogPath -Message "Valid monitored directory: $($Directory.path) (exclusions: $($Directory.exclusions.Count))"
        return $true
    }
    catch {
        Write-LogWarning -LogPath $LogPath -Message "Error validating monitored directory" -Exception $_.Exception
        return $false
    }
}

# Export all public functions
Export-ModuleMember -Function Read-SettingsFile, New-SettingsFile, Set-StagingArea, Add-DriveMapping, Remove-DriveMapping, Set-DriveMapping, Add-MonitoredDirectory, Remove-MonitoredDirectory, Set-MonitoredDirectory