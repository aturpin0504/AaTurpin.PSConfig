function Read-SettingsFile {
    <#
    .SYNOPSIS
        Reads and parses the settings.json configuration file with validation.
    
    .DESCRIPTION
        This cmdlet reads the settings.json file, parses the JSON content, validates
        drive mappings and monitored directories, and returns a PowerShell object
        containing the configuration settings. If the settings file doesn't exist,
        it will be created automatically using New-SettingsFile.
        
        The function now pre-compiles regex patterns for monitored directory exclusions
        to improve performance during file system operations. Original exclusions are
        preserved for readability and configuration management.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $config = Read-SettingsFile -LogPath "C:\Logs\app.log"
    
    .EXAMPLE
        $config = Read-SettingsFile -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
    
    .OUTPUTS
        PSCustomObject containing the validated settings configuration with pre-compiled exclusion patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-LogDebug -LogPath $LogPath -Message "Reading settings from: $SettingsPath"
    
    # Memory management: Cleanup compiled patterns on error
    trap {
        Write-LogError -LogPath $LogPath -Message "Critical error occurred, cleaning up compiled regex patterns" -Exception $_.Exception
        if ($settings -and $settings.monitoredDirectories) {
            $settings.monitoredDirectories | ForEach-Object {
                if ($_.compiledExclusionPatterns) {
                    $_.compiledExclusionPatterns | ForEach-Object { 
                        try { $_.Dispose() } catch { } 
                    }
                    $_.compiledExclusionPatterns = @()
                }
            }
        }
        throw
    }
    
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
        
        # Validate monitored directories and pre-compile exclusion patterns
        $validMonitoredDirs = @()
        if ($settings.monitoredDirectories -and $settings.monitoredDirectories.Count -gt 0) {
            foreach ($directory in $settings.monitoredDirectories) {
                if (Test-MonitoredDirectory -Directory $directory -LogPath $LogPath) {
                    # Pre-compile exclusion patterns for performance
                    if ($directory.exclusions -and $directory.exclusions.Count -gt 0) {
                        try {
                            # Normalize exclusions (trim slashes, convert to backslashes, lowercase)
                            $normalizedExclusions = $directory.exclusions | ForEach-Object {
                                $_.Trim('\', '/').Replace('/', '\').ToLowerInvariant()
                            }
                            
                            # Create compiled regex patterns for exact matching
                            $exclusionPatterns = $normalizedExclusions | ForEach-Object {
                                try {
                                    [regex]::new("^$([regex]::Escape($_))($|\\)", 
                                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor 
                                        [System.Text.RegularExpressions.RegexOptions]::Compiled)
                                }
                                catch [System.ArgumentException] {
                                    Write-LogWarning -LogPath $LogPath -Message "Invalid regex pattern in exclusion '$_' for directory '$($directory.path)': $($_.Exception.Message)"
                                    $null  # Skip this pattern
                                }
                                catch {
                                    Write-LogWarning -LogPath $LogPath -Message "Unexpected error compiling exclusion '$_' for directory '$($directory.path)': $($_.Exception.Message)"
                                    $null  # Skip this pattern
                                }
                            } | Where-Object { $_ -ne $null }  # Filter out failed patterns
                            
                            # Add compiled patterns as a separate property (preserving original exclusions)
                            $directory | Add-Member -MemberType NoteProperty -Name "compiledExclusionPatterns" -Value $exclusionPatterns -Force
                            
                            $successCount = $exclusionPatterns.Count
                            $totalCount = $directory.exclusions.Count
                            if ($successCount -eq $totalCount) {
                                Write-LogDebug -LogPath $LogPath -Message "Pre-compiled $successCount exclusion patterns for directory: $($directory.path)"
                            } else {
                                Write-LogWarning -LogPath $LogPath -Message "Pre-compiled $successCount of $totalCount exclusion patterns for directory: $($directory.path) (some patterns failed)"
                            }
                        }
                        catch [System.ArgumentException] {
                            Write-LogWarning -LogPath $LogPath -Message "Invalid regex pattern in exclusions for directory '$($directory.path)': $($_.Exception.Message)" -Exception $_.Exception
                            # Add empty patterns array if compilation fails
                            $directory | Add-Member -MemberType NoteProperty -Name "compiledExclusionPatterns" -Value @() -Force
                        }
                        catch {
                            Write-LogWarning -LogPath $LogPath -Message "Unexpected error compiling exclusion patterns for directory '$($directory.path)': $($_.Exception.Message)" -Exception $_.Exception
                            # Add empty patterns array if compilation fails
                            $directory | Add-Member -MemberType NoteProperty -Name "compiledExclusionPatterns" -Value @() -Force
                        }
                    }
                    else {
                        # No exclusions to compile - add empty patterns array
                        $directory | Add-Member -MemberType NoteProperty -Name "compiledExclusionPatterns" -Value @() -Force
                        Write-LogDebug -LogPath $LogPath -Message "No exclusions to compile for directory: $($directory.path)"
                    }
                    
                    $validMonitoredDirs += $directory
                }
            }
        }
        $settings.monitoredDirectories = $validMonitoredDirs
        
        $totalPatterns = ($validMonitoredDirs | ForEach-Object { $_.compiledExclusionPatterns.Count } | Measure-Object -Sum).Sum
        Write-LogDebug -LogPath $LogPath -Message "Configuration loaded: $($validDriveMappings.Count) drive mappings, $($validMonitoredDirs.Count) monitored directories, $totalPatterns total compiled exclusion patterns"
        
        return $settings
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to read settings file" -Exception $_.Exception
        throw
    }
}

function Show-Settings {
    <#
    .SYNOPSIS
        Displays configuration settings with detailed information and current system status.
    
    .DESCRIPTION
        This cmdlet reads the settings.json file and displays a comprehensive summary
        of the current configuration including staging area, drive mappings, and monitored
        directories. It shows both the configured values and their current system status,
        providing administrators with a complete view of the configuration state.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .PARAMETER ShowDetails
        If specified, displays detailed information including exclusion patterns and system status.
    
    .EXAMPLE
        Show-Settings -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        
        Displays basic configuration summary.
    
    .EXAMPLE
        Show-Settings -SettingsPath "settings.json" -LogPath "app.log" -ShowDetails
        
        Displays detailed configuration information including exclusions and system status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowDetails
    )
    
    Write-Host "`nConfiguration Report" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Cyan
    Write-LogInfo -LogPath $LogPath -Message "Generating configuration report for: $SettingsPath"
 
    try {
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        # Configuration file information
        Write-Host "`nConfiguration File:" -ForegroundColor Yellow
        $absolutePath = Resolve-Path $SettingsPath -ErrorAction SilentlyContinue
        if ($absolutePath) {
            Write-Host "  Location: $($absolutePath.Path)" -ForegroundColor White
            $fileInfo = Get-Item $absolutePath.Path
            Write-Host "  Last Modified: $($fileInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
            Write-Host "  Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor White
        } else {
            Write-Host "  Location: $SettingsPath (not found)" -ForegroundColor Red
        }
        
        # Staging area information - FIX: Remove duplication
        Write-Host "`nStaging Area:" -ForegroundColor Yellow
        Write-Host "  Path: $($settings.stagingArea)" -ForegroundColor White
        $stagingExists = Test-Path $settings.stagingArea
        $stagingStatus = if ($stagingExists) { "✓ Exists" } else { "✗ Not Found" }
        $stagingColor = if ($stagingExists) { "Green" } else { "Red" }
        Write-Host "  Status: $stagingStatus" -ForegroundColor $stagingColor
        
        if ($stagingExists -and $ShowDetails) {
            try {
                $stagingInfo = Get-Item $settings.stagingArea
                Write-Host "  Created: $($stagingInfo.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
                
                # Use .NET DirectoryInfo for efficient file counting
                $dirInfo = [System.IO.DirectoryInfo]::new($settings.stagingArea)
                $fileCount = 0
                $dirCount = 0
                
                try {
                    # Count files and directories efficiently
                    $files = $dirInfo.GetFiles("*", [System.IO.SearchOption]::AllDirectories)
                    $directories = $dirInfo.GetDirectories("*", [System.IO.SearchOption]::AllDirectories)
                    $fileCount = $files.Count
                    $dirCount = $directories.Count
                    
                    $totalItems = $fileCount + $dirCount
                    Write-Host "  Contents: $totalItems items ($fileCount files, $dirCount directories)" -ForegroundColor Gray
                    
                    # Optionally show size information for files
                    if ($fileCount -gt 0) {
                        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
                        $formattedSize = if ($totalSize -ge 1GB) { 
                            "$([math]::Round($totalSize / 1GB, 2)) GB" 
                        } elseif ($totalSize -ge 1MB) { 
                            "$([math]::Round($totalSize / 1MB, 2)) MB" 
                        } elseif ($totalSize -ge 1KB) { 
                            "$([math]::Round($totalSize / 1KB, 2)) KB" 
                        } else { 
                            "$totalSize bytes" 
                        }
                        Write-Host "  Total Size: $formattedSize" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "  Contents: Unable to enumerate items" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "  Additional info: Unable to access" -ForegroundColor Yellow
            }
        }
        
        # Drive mappings information
        $displayableMappings = $settings.driveMappings | Where-Object { $_ -ne $null }
        Write-Host "`nDrive Mappings: $($displayableMappings.Count)" -ForegroundColor Yellow
        if ($displayableMappings.Count -eq 0) {
            Write-Host "  No drive mappings configured" -ForegroundColor Gray
        } else {
            foreach ($mapping in $displayableMappings) {
                $driveExists = Test-Path "$($mapping.letter):\"
                $driveStatus = if ($driveExists) { "✓ Mapped" } else { "✗ Not Mapped" }
                $driveColor = if ($driveExists) { "Green" } else { "Red" }
                
                Write-Host "  $($mapping.letter): -> $($mapping.path)" -ForegroundColor White
                Write-Host "    Status: $driveStatus" -ForegroundColor $driveColor
                
                if ($ShowDetails) {
                    if ($driveExists) {
                        try {
                            $currentMapping = Get-PSDrive -Name $mapping.letter -ErrorAction SilentlyContinue
                            if ($currentMapping -and $currentMapping.DisplayRoot) {
                                $actualPath = $currentMapping.DisplayRoot
                                $pathMatch = ($actualPath -eq $mapping.path)
                                $pathStatus = if ($pathMatch) { "✓ Correct Path" } else { "⚠ Different Path: $actualPath" }
                                $pathColor = if ($pathMatch) { "Green" } else { "Yellow" }
                                Write-Host "    Path Check: $pathStatus" -ForegroundColor $pathColor
                            }
                        }
                        catch {
                            Write-Host "    Path Check: Unable to verify" -ForegroundColor Yellow
                        }
                    }
                    
                    # Test network path accessibility
                    try {
                        $pathAccessible = Test-Path $mapping.path -ErrorAction SilentlyContinue
                        $accessStatus = if ($pathAccessible) { "✓ Accessible" } else { "✗ Not Accessible" }
                        $accessColor = if ($pathAccessible) { "Green" } else { "Red" }
                        Write-Host "    Network Path: $accessStatus" -ForegroundColor $accessColor
                    }
                    catch {
                        Write-Host "    Network Path: Unable to test" -ForegroundColor Yellow
                    }
                }
            }
        }
        
        # Monitored directories information
        Write-Host "`nMonitored Directories: $($settings.monitoredDirectories.Count)" -ForegroundColor Yellow
        if ($settings.monitoredDirectories.Count -eq 0) {
            Write-Host "  No monitored directories configured" -ForegroundColor Gray
        } else {
            $totalExclusions = ($settings.monitoredDirectories | ForEach-Object { $_.exclusions.Count } | Measure-Object -Sum).Sum
            $totalCompiledPatterns = ($settings.monitoredDirectories | ForEach-Object { $_.compiledExclusionPatterns.Count } | Measure-Object -Sum).Sum
            
            Write-Host "  Total Exclusion Patterns: $totalExclusions (compiled: $totalCompiledPatterns)" -ForegroundColor Gray
            Write-Host ""
            
            foreach ($directory in $settings.monitoredDirectories) {
                $exclusionCount = if ($directory.exclusions) { $directory.exclusions.Count } else { 0 }
                $compiledCount = if ($directory.compiledExclusionPatterns) { $directory.compiledExclusionPatterns.Count } else { 0 }
                
                Write-Host "  $($directory.path)" -ForegroundColor White
                Write-Host "    Exclusions: $exclusionCount patterns ($compiledCount compiled)" -ForegroundColor Gray
                
                if ($ShowDetails) {
                    # Test directory accessibility
                    try {
                        $dirAccessible = Test-Path $directory.path -ErrorAction SilentlyContinue
                        $dirStatus = if ($dirAccessible) { "✓ Accessible" } else { "✗ Not Accessible" }
                        $dirColor = if ($dirAccessible) { "Green" } else { "Red" }
                        Write-Host "    Status: $dirStatus" -ForegroundColor $dirColor
                        
                        # Show exclusion patterns if any
                        if ($exclusionCount -gt 0 -and $directory.exclusions) {
                            Write-Host "    Exclusion Patterns:" -ForegroundColor Gray
                            foreach ($exclusion in $directory.exclusions) {
                                Write-Host "      - $exclusion" -ForegroundColor DarkGray
                            }
                        }
                        
                        # Show compilation status
                        if ($exclusionCount -ne $compiledCount) {
                            Write-Host "    Warning: $($exclusionCount - $compiledCount) patterns failed to compile" -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Host "    Status: Unable to test" -ForegroundColor Yellow
                    }
                }
            }
        }
        
        # Summary statistics
        Write-Host "`nSummary:" -ForegroundColor Yellow
        Write-Host "  Configuration Status: Valid" -ForegroundColor Green
        
        if ($ShowDetails) {
            # Fix: Ensure we get proper counts for accessible items
            $accessibleDrives = @($displayableMappings | Where-Object { 
                Test-Path "$($_.letter):\" -ErrorAction SilentlyContinue 
            })
    
            $accessibleDirs = @($settings.monitoredDirectories | Where-Object { 
                Test-Path $_.path -ErrorAction SilentlyContinue 
            })
            
            $driveAccessibleCount = $accessibleDrives.Count
            $dirAccessibleCount = $accessibleDirs.Count
            $totalMappings = $displayableMappings.Count
            $totalDirs = $settings.monitoredDirectories.Count
    
            Write-Host "  Drive Mappings: $driveAccessibleCount/$totalMappings accessible" -ForegroundColor $(if ($driveAccessibleCount -eq $totalMappings) { "Green" } else { "Yellow" })
            Write-Host "  Monitored Directories: $dirAccessibleCount/$totalDirs accessible" -ForegroundColor $(if ($dirAccessibleCount -eq $totalDirs) { "Green" } else { "Yellow" })
    
            # Fix regex pattern counting with safe arithmetic
            $totalExclusions = 0
            $totalCompiledPatterns = 0
    
            foreach ($dir in $settings.monitoredDirectories) {
                if ($dir.exclusions) {
                    $totalExclusions += $dir.exclusions.Count
                }
                if ($dir.compiledExclusionPatterns) {
                    $totalCompiledPatterns += $dir.compiledExclusionPatterns.Count
                }
            }
    
            Write-Host "  Regex Patterns: $totalCompiledPatterns/$totalExclusions compiled successfully" -ForegroundColor $(if ($totalCompiledPatterns -eq $totalExclusions) { "Green" } else { "Yellow" })
        }
        
        Write-Host "`nConfiguration report completed." -ForegroundColor Green
        Write-LogInfo -LogPath $LogPath -Message "Configuration report completed successfully - $($settings.driveMappings.Count) drive mappings, $($settings.monitoredDirectories.Count) monitored directories"
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to generate configuration report" -Exception $_.Exception
        Write-Host "`nError generating configuration report: $($_.Exception.Message)" -ForegroundColor Red
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
        
        # Validate path format - allow both UNC paths and local drive paths
        if ([string]::IsNullOrWhiteSpace($Mapping.path) -or $Mapping.path.Length -le 2) {
            Write-LogWarning -LogPath $LogPath -Message "Invalid path for drive $($Mapping.letter): '$($Mapping.path)'"
            return $false
        }
        
        # Check if it's a UNC path or local drive path
        $isUncPath = $Mapping.path.StartsWith("\\")
        $isLocalDrivePath = $Mapping.path -match "^[A-Za-z]:\\.*"
        
        if (-not $isUncPath -and -not $isLocalDrivePath) {
            Write-LogWarning -LogPath $LogPath -Message "Invalid path format for drive $($Mapping.letter): '$($Mapping.path)' (must be UNC path or local drive path)"
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

function Show-MultiSelectMenu {
    <#
    .SYNOPSIS
        Displays an interactive multi-select menu in the PowerShell console.
    
    .DESCRIPTION
        Creates a console-based menu where users can navigate with arrow keys,
        select/deselect items with spacebar, and confirm selections with Enter.
        Visual feedback shows selected items with [X] and unselected with [ ].
        Uses default console colors only. Optimized for fast refresh rates.
    
    .PARAMETER Title
        The title to display at the top of the menu.
    
    .PARAMETER Options
        Array of menu options to display.
    
    .PARAMETER AllowEmpty
        Whether to allow confirming with no selections (default: $false).
    
    .PARAMETER ShowInstructions
        Whether to show navigation instructions (default: $true).
    
    .EXAMPLE
        $options = @("Option 1", "Option 2", "Option 3", "Option 4")
        $selected = Show-MultiSelectMenu -Title "Select Multiple Options" -Options $options
        Write-Host "You selected: $($selected -join ', ')"
    
    .EXAMPLE
        $services = Get-Service | Select-Object -First 10 -ExpandProperty Name
        $selectedServices = Show-MultiSelectMenu -Title "Select Services to Restart" -Options $services -AllowEmpty
    
    .OUTPUTS
        Array of selected option strings
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
        [string[]]$Options,
        
        [Parameter(Mandatory = $false)]
        [bool]$AllowEmpty = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ShowInstructions = $true
    )
    
    # Validate input
    if ($Options.Count -eq 0) {
        throw "Options array cannot be empty"
    }
    
    # Initialize state
    $currentIndex = 0
    $selectedItems = @()
    $maxDisplayLength = 70
    
    # Check if RawUI ReadKey is available - better detection method
    $useRawInput = $false
    try {
        # Check if we're in a supported host environment
        $hostName = $Host.Name
        if ($hostName -eq "ConsoleHost" -or $hostName -eq "Windows PowerShell ISE Host") {
            # Additional check for RawUI capabilities
            if ($Host.UI.RawUI -and $Host.UI.RawUI.KeyAvailable -ne $null) {
                $useRawInput = $true
            }
        }
        # For ISE, we know ReadKey doesn't work properly
        if ($hostName -eq "Windows PowerShell ISE Host") {
            $useRawInput = $false
        }
    }
    catch {
        $useRawInput = $false
    }
    
    if (-not $useRawInput) {
        Write-Host ""
        Write-Host "Note: Enhanced keyboard input not available in this environment."
        Write-Host "Using fallback input method. Use number keys to toggle selections."
        Write-Host ""
    }
    
    # Function to clear console and redraw menu
    function Show-Menu {
        Clear-Host

        # Display title
        Write-Host ""
        Write-Host " $Title"
        Write-Host " $('=' * $Title.Length)"
        Write-Host ""

        # Display options
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $option = $Options[$i]
            $isSelected = $selectedItems -contains $i
            $isCurrent = ($i -eq $currentIndex) -and $useRawInput

            # Truncate long options
            $displayOption = if ($option.Length -gt $maxDisplayLength) {
                $option.Substring(0, $maxDisplayLength - 3) + "..."
            } else {
                $option
            }

            # Build display components
            $checkbox = if ($isSelected) { "[X]" } else { "[ ]" }
            $number = if (-not $useRawInput) { "($($i + 1))" } else { "   " }
            $prefix = if ($isCurrent) { ">" } else { " " }
            
            # Construct the complete line as a single string
            $line = " $prefix $checkbox $number $displayOption"

            # Display with highlight for current item only (using background color)
            if ($isCurrent) {
                # Current item gets inverted colors (background/foreground swap)
                Write-Host $line -ForegroundColor Black -BackgroundColor White
            } else {
                # All other items use default console colors
                Write-Host $line
            }
        }

        # Display instructions
        if ($ShowInstructions) {
            Write-Host ""
            Write-Host " Instructions:"
            if ($useRawInput) {
                Write-Host "   Up/Down or k/j  Navigate"
                Write-Host "   Space           Toggle selection"
                Write-Host "   Enter           Confirm selection"
                Write-Host "   Esc or q        Cancel"
                Write-Host "   a               Select all"
                Write-Host "   c               Clear all"
            } else {
                Write-Host "   1-$($Options.Count)          Toggle item selection"
                Write-Host "   a               Select all"
                Write-Host "   c               Clear all"
                Write-Host "   Enter           Confirm selection"
                Write-Host "   q               Cancel"
            }
        }

        # Display selection status
        Write-Host ""
        if ($selectedItems.Count -eq 0) {
            Write-Host " No items selected"
            if (-not $AllowEmpty) {
                Write-Host " (At least one item must be selected)"
            }
        } 
        elseif ($selectedItems.Count -eq 1) {
            Write-Host " 1 item selected"
        } 
        else {
            Write-Host " $($selectedItems.Count) items selected"
        }

        # Show command prompt for fallback mode
        if (-not $useRawInput) {
            Write-Host ""
            Write-Host " Commands: [1-$($Options.Count)] Toggle item | [a] Select all | [c] Clear all | [Enter] Confirm | [q] Quit"
            Write-Host ""
            Write-Host " Enter command: " -NoNewline
        }
    }

    # Main menu loop
    try {
        while ($true) {
            Show-Menu
            
            if ($useRawInput) {
                # Enhanced input method (regular PowerShell console)
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                switch ($key.VirtualKeyCode) {
                    # Up Arrow or 'k'
                    { $_ -eq 38 -or ($key.Character -eq 'k') } {
                        $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $Options.Count - 1 }
                    }
                    
                    # Down Arrow or 'j'
                    { $_ -eq 40 -or ($key.Character -eq 'j') } {
                        $currentIndex = if ($currentIndex -lt ($Options.Count - 1)) { $currentIndex + 1 } else { 0 }
                    }
                    
                    # Spacebar - Toggle selection
                    32 {
                        if ($selectedItems -contains $currentIndex) {
                            $selectedItems = $selectedItems | Where-Object { $_ -ne $currentIndex }
                        } else {
                            $selectedItems += $currentIndex
                        }
                    }
                    
                    # Enter - Confirm selection
                    13 {
                        if ($AllowEmpty -or $selectedItems.Count -gt 0) {
                            $result = $selectedItems | Sort-Object | ForEach-Object { $Options[$_] }
                            Clear-Host
                            return $result
                        }
                    }
                    
                    # Escape or 'q' - Cancel
                    { $_ -eq 27 -or ($key.Character -eq 'q') } {
                        Clear-Host
                        Write-Host "Selection cancelled."
                        return @()
                    }
                    
                    # 'a' - Select all
                    { $key.Character -eq 'a' } {
                        $selectedItems = 0..($Options.Count - 1)
                    }
                    
                    # 'c' - Clear all
                    { $key.Character -eq 'c' } {
                        $selectedItems = @()
                    }
                    
                    # Home - Go to first item
                    36 {
                        $currentIndex = 0
                    }
                    
                    # End - Go to last item
                    35 {
                        $currentIndex = $Options.Count - 1
                    }
                }
            }
            else {
                # Fallback method for environments without RawUI support
                $input = Read-Host
                
                switch -Regex ($input.Trim().ToLower()) {
                    '^[0-9]+$' {
                        $index = [int]$input - 1
                        if ($index -ge 0 -and $index -lt $Options.Count) {
                            if ($selectedItems -contains $index) {
                                $selectedItems = $selectedItems | Where-Object { $_ -ne $index }
                            } else {
                                $selectedItems += $index
                            }
                            # Menu will refresh immediately on next loop iteration
                        } else {
                            Write-Host " Invalid option number. Please enter 1-$($Options.Count)" -ForegroundColor Red
                            Start-Sleep -Milliseconds 800  # Brief pause only for errors
                        }
                    }
                    
                    '^a$' {
                        $selectedItems = 0..($Options.Count - 1)
                        # Menu will refresh immediately on next loop iteration
                    }
                    
                    '^c$' {
                        $selectedItems = @()
                        # Menu will refresh immediately on next loop iteration
                    }
                    
                    '^$' {
                        # Enter key (empty input)
                        if ($AllowEmpty -or $selectedItems.Count -gt 0) {
                            $result = $selectedItems | Sort-Object | ForEach-Object { $Options[$_] }
                            Clear-Host
                            return $result
                        } else {
                            Write-Host " Please select at least one item" -ForegroundColor Yellow
                            Start-Sleep -Milliseconds 800  # Brief pause only for errors
                        }
                    }
                    
                    '^q$' {
                        Clear-Host
                        Write-Host "Selection cancelled."
                        return @()
                    }
                    
                    default {
                        Write-Host " Invalid command. Use number (1-$($Options.Count)), 'a', 'c', Enter, or 'q'" -ForegroundColor Red
                        Start-Sleep -Milliseconds 800  # Brief pause only for errors
                    }
                }
            }
        }
    }
    catch {
        Clear-Host
        Write-Error "An error occurred: $($_.Exception.Message)"
        return @()
    }
}

function Add-DriveMappingInteractive {
    <#
    .SYNOPSIS
        Interactively adds a new drive mapping to the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for adding a new drive mapping.
        It prompts the user for the drive letter and UNC path, validates the input,
        and adds the mapping to the settings.json file after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Add-DriveMappingInteractive -LogPath "C:\Logs\app.log"
        Interactively prompts for drive mapping details and adds it to the default settings file.
    
    .EXAMPLE
        $config = Add-DriveMappingInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Adds a drive mapping to the specified settings file using interactive prompts.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive drive mapping addition"
    
    Write-Host "`nAdd New Drive Mapping" -ForegroundColor Yellow
    Write-Host "=" * 25 -ForegroundColor Yellow
    
    try {
        # Get drive letter with validation
        do {
            $driveLetter = Read-Host "Enter drive letter (A-Z)"
            if ([string]::IsNullOrWhiteSpace($driveLetter) -or $driveLetter.Length -ne 1 -or -not [char]::IsLetter($driveLetter)) {
                Write-Host "Please enter a single alphabetic character" -ForegroundColor Red
                Write-LogWarning -LogPath $LogPath -Message "Invalid drive letter entered: '$driveLetter'"
                $driveLetter = $null
            }
        } while (-not $driveLetter)
        
        # Get UNC path with validation
        do {
            $uncPath = Read-Host "Enter UNC path (e.g., \\server\share)"
            if ([string]::IsNullOrWhiteSpace($uncPath) -or -not $uncPath.StartsWith("\\") -or $uncPath.Length -le 2) {
                Write-Host "Please enter a valid UNC path starting with \\" -ForegroundColor Red
                Write-LogWarning -LogPath $LogPath -Message "Invalid UNC path entered: '$uncPath'"
                $uncPath = $null
            }
        } while (-not $uncPath)
        
        # Confirm and add
        Write-Host "`nAdding drive mapping: $($driveLetter.ToUpper()) -> $uncPath" -ForegroundColor Green
        $confirm = Read-Host "Confirm? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Drive mapping '$($driveLetter.ToUpper())'", "Add mapping to '$uncPath'")) {
                $updatedSettings = Add-DriveMapping -Letter $driveLetter -Path $uncPath -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Drive mapping added successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping addition completed successfully: $($driveLetter.ToUpper()) -> $uncPath"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping addition cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to add drive mapping interactively" -Exception $_.Exception
        Write-Host "Error adding drive mapping: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

function Remove-DriveMappingInteractive {
    <#
    .SYNOPSIS
        Interactively removes a drive mapping from the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for removing an existing drive mapping.
        It displays available mappings for selection and removes the chosen mapping
        after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Remove-DriveMappingInteractive -LogPath "C:\Logs\app.log"
        Interactively removes a drive mapping from the default settings file.
    
    .EXAMPLE
        $config = Remove-DriveMappingInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Removes a drive mapping from the specified settings file using interactive selection.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled or no mappings exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive drive mapping removal"
    
    Write-Host "`nRemove Drive Mapping" -ForegroundColor Yellow
    Write-Host "=" * 20 -ForegroundColor Yellow
    
    try {
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        if ($settings.driveMappings.Count -eq 0) {
            Write-Host "No drive mappings configured to remove." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "No drive mappings available for removal"
            
            Read-Host "Press Enter to continue"
            return $null
        }
        
        # Create options for selection
        $mappingOptions = $settings.driveMappings | ForEach-Object { "$($_.letter): -> $($_.path)" }
        
        $selection = Show-MultiSelectMenu -Title "Select drive mapping to remove" -Options $mappingOptions -AllowEmpty $true
        
        if ($selection.Count -eq 0) {
            Write-Host "No selection made. Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping removal cancelled - no selection made"
            return $null
        }
        
        # Extract drive letter from selection
        $selectedMapping = $selection[0]
        $driveLetter = $selectedMapping.Split(':')[0]
        
        # Confirm removal
        Write-Host "`nRemoving drive mapping: $selectedMapping" -ForegroundColor Red
        $confirm = Read-Host "Are you sure? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Drive mapping '$driveLetter'", "Remove mapping")) {
                $updatedSettings = Remove-DriveMapping -Letter $driveLetter -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Drive mapping removed successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping removal completed successfully: $selectedMapping"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping removal cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to remove drive mapping interactively" -Exception $_.Exception
        Write-Host "Error removing drive mapping: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

function Set-DriveMappingInteractive {
    <#
    .SYNOPSIS
        Interactively modifies an existing drive mapping in the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for modifying an existing drive mapping.
        It displays available mappings for selection and prompts for a new UNC path,
        updating the mapping after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Set-DriveMappingInteractive -LogPath "C:\Logs\app.log"
        Interactively modifies a drive mapping in the default settings file.
    
    .EXAMPLE
        $config = Set-DriveMappingInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Modifies a drive mapping in the specified settings file using interactive prompts.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled or no mappings exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive drive mapping modification"
    
    Write-Host "`nModify Drive Mapping" -ForegroundColor Yellow
    Write-Host "=" * 20 -ForegroundColor Yellow
    
    try {
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        if ($settings.driveMappings.Count -eq 0) {
            Write-Host "No drive mappings configured to modify." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "No drive mappings available for modification"
            
            Read-Host "Press Enter to continue"
            return $null
        }
        
        # Create options for selection
        $mappingOptions = $settings.driveMappings | ForEach-Object { "$($_.letter): -> $($_.path)" }
        
        $selection = Show-MultiSelectMenu -Title "Select drive mapping to modify" -Options $mappingOptions -AllowEmpty $true
        
        if ($selection.Count -eq 0) {
            Write-Host "No selection made. Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping modification cancelled - no selection made"
            return $null
        }
        
        # Extract drive letter from selection
        $selectedMapping = $selection[0]
        $driveLetter = $selectedMapping.Split(':')[0]
        $currentPath = ($settings.driveMappings | Where-Object { $_.letter -eq $driveLetter }).path
        
        Write-Host "`nCurrent path for drive $driveLetter`: $currentPath" -ForegroundColor Cyan
        
        # Get new UNC path with validation
        do {
            $newUncPath = Read-Host "Enter new UNC path (e.g., \\server\share)"
            if ([string]::IsNullOrWhiteSpace($newUncPath) -or -not $newUncPath.StartsWith("\\") -or $newUncPath.Length -le 2) {
                Write-Host "Please enter a valid UNC path starting with \\" -ForegroundColor Red
                Write-LogWarning -LogPath $LogPath -Message "Invalid UNC path entered: '$newUncPath'"
                $newUncPath = $null
            }
        } while (-not $newUncPath)
        
        # Confirm modification
        Write-Host "`nModifying drive mapping: $driveLetter" -ForegroundColor Green
        Write-Host "  From: $currentPath" -ForegroundColor Gray
        Write-Host "  To:   $newUncPath" -ForegroundColor Gray
        $confirm = Read-Host "Confirm? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Drive mapping '$driveLetter'", "Update path from '$currentPath' to '$newUncPath'")) {
                $updatedSettings = Set-DriveMapping -Letter $driveLetter -Path $newUncPath -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Drive mapping modified successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping modification completed successfully: $driveLetter from '$currentPath' to '$newUncPath'"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive drive mapping modification cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to modify drive mapping interactively" -Exception $_.Exception
        Write-Host "Error modifying drive mapping: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

function Add-MonitoredDirectoryInteractive {
    <#
    .SYNOPSIS
        Interactively adds a new monitored directory to the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for adding a new monitored directory.
        It prompts the user for the directory path and optional exclusion patterns,
        validates the input, and adds the directory to the settings.json file after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Add-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
        Interactively prompts for monitored directory details and adds it to the default settings file.
    
    .EXAMPLE
        $config = Add-MonitoredDirectoryInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Adds a monitored directory to the specified settings file using interactive prompts.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive monitored directory addition"
    
    Write-Host "`nAdd New Monitored Directory" -ForegroundColor Yellow
    Write-Host "=" * 30 -ForegroundColor Yellow
    
    try {
        # Get directory path with validation
        do {
            $directoryPath = Read-Host "Enter directory path to monitor"
            if ([string]::IsNullOrWhiteSpace($directoryPath)) {
                Write-Host "Please enter a valid directory path" -ForegroundColor Red
                Write-LogWarning -LogPath $LogPath -Message "Invalid directory path entered: '$directoryPath'"
                $directoryPath = $null
            }
        } while (-not $directoryPath)
        
        # Get exclusions
        Write-Host "`nEnter exclusion patterns (subdirectory names to exclude):" -ForegroundColor Cyan
        Write-Host "Leave blank and press Enter when done" -ForegroundColor Gray
        
        $exclusions = @()
        $exclusionIndex = 1
        
        while ($true) {
            $exclusion = Read-Host "Exclusion $exclusionIndex (or Enter to finish)"
            if ([string]::IsNullOrWhiteSpace($exclusion)) {
                break
            }
            $exclusions += $exclusion.Trim()
            $exclusionIndex++
        }
        
        Write-LogDebug -LogPath $LogPath -Message "Collected exclusions for '$directoryPath': $($exclusions.Count) items"
        
        # Confirm and add
        Write-Host "`nAdding monitored directory:" -ForegroundColor Green
        Write-Host "  Path: $directoryPath" -ForegroundColor White
        Write-Host "  Exclusions: $($exclusions.Count) items" -ForegroundColor White
        if ($exclusions.Count -gt 0) {
            $exclusions | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        }
        
        $confirm = Read-Host "Confirm? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Monitored directory '$directoryPath'", "Add with $($exclusions.Count) exclusions")) {
                $updatedSettings = Add-MonitoredDirectory -Path $directoryPath -Exclusions $exclusions -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Monitored directory added successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory addition completed successfully: '$directoryPath' with $($exclusions.Count) exclusions"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory addition cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to add monitored directory interactively" -Exception $_.Exception
        Write-Host "Error adding monitored directory: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

function Remove-MonitoredDirectoryInteractive {
    <#
    .SYNOPSIS
        Interactively removes a monitored directory from the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for removing an existing monitored directory.
        It displays available directories for selection and removes the chosen directory
        after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Remove-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
        Interactively removes a monitored directory from the default settings file.
    
    .EXAMPLE
        $config = Remove-MonitoredDirectoryInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Removes a monitored directory from the specified settings file using interactive selection.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled or no directories exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive monitored directory removal"
    
    Write-Host "`nRemove Monitored Directory" -ForegroundColor Yellow
    Write-Host "=" * 28 -ForegroundColor Yellow
    
    try {
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        if ($settings.monitoredDirectories.Count -eq 0) {
            Write-Host "No monitored directories configured to remove." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "No monitored directories available for removal"
            
            Read-Host "Press Enter to continue"
            return $null
        }
        
        # Create options for selection
        $directoryOptions = $settings.monitoredDirectories | ForEach-Object { 
            $exclusionCount = if ($_.exclusions) { $_.exclusions.Count } else { 0 }
            "$($_.path) ($exclusionCount exclusions)"
        }
        
        $selection = Show-MultiSelectMenu -Title "Select monitored directory to remove" -Options $directoryOptions -AllowEmpty $true
        
        if ($selection.Count -eq 0) {
            Write-Host "No selection made. Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory removal cancelled - no selection made"
            return $null
        }
        
        # Extract path from selection
        $selectedDirectory = $selection[0]
        $directoryPath = $selectedDirectory -replace ' \(\d+ exclusions\)$', ''
        
        # Confirm removal
        Write-Host "`nRemoving monitored directory: $directoryPath" -ForegroundColor Red
        $confirm = Read-Host "Are you sure? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Monitored directory '$directoryPath'", "Remove directory")) {
                $updatedSettings = Remove-MonitoredDirectory -Path $directoryPath -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Monitored directory removed successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory removal completed successfully: '$directoryPath'"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory removal cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to remove monitored directory interactively" -Exception $_.Exception
        Write-Host "Error removing monitored directory: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

function Set-MonitoredDirectoryInteractive {
    <#
    .SYNOPSIS
        Interactively modifies an existing monitored directory in the configuration file.
    
    .DESCRIPTION
        This cmdlet provides an interactive interface for modifying an existing monitored directory.
        It displays available directories for selection and prompts for new exclusion patterns,
        updating the directory configuration after user confirmation.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in current directory.
    
    .PARAMETER LogPath
        The path to the log file where operations will be logged using PSLogger.
    
    .EXAMPLE
        $settings = Set-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
        Interactively modifies a monitored directory in the default settings file.
    
    .EXAMPLE
        $config = Set-MonitoredDirectoryInteractive -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Modifies a monitored directory in the specified settings file using interactive prompts.
    
    .OUTPUTS
        PSCustomObject containing the updated settings configuration, or $null if operation was cancelled or no directories exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )
    
    Write-LogInfo -LogPath $LogPath -Message "Starting interactive monitored directory modification"
    
    Write-Host "`nModify Monitored Directory" -ForegroundColor Yellow
    Write-Host "=" * 28 -ForegroundColor Yellow
    
    try {
        $settings = Read-SettingsFile -SettingsPath $SettingsPath -LogPath $LogPath
        
        if ($settings.monitoredDirectories.Count -eq 0) {
            Write-Host "No monitored directories configured to modify." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "No monitored directories available for modification"
            
            Read-Host "Press Enter to continue"
            return $null
        }
        
        # Create options for selection
        $directoryOptions = $settings.monitoredDirectories | ForEach-Object { 
            $exclusionCount = if ($_.exclusions) { $_.exclusions.Count } else { 0 }
            "$($_.path) ($exclusionCount exclusions)"
        }
        
        $selection = Show-MultiSelectMenu -Title "Select monitored directory to modify" -Options $directoryOptions -AllowEmpty $true
        
        if ($selection.Count -eq 0) {
            Write-Host "No selection made. Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory modification cancelled - no selection made"
            return $null
        }
        
        # Extract path from selection
        $selectedDirectory = $selection[0]
        $directoryPath = $selectedDirectory -replace ' \(\d+ exclusions\)$', ''
        $currentDir = $settings.monitoredDirectories | Where-Object { $_.path -eq $directoryPath }
        
        Write-Host "`nModifying exclusions for: $directoryPath" -ForegroundColor Cyan
        Write-Host "Current exclusions:" -ForegroundColor Gray
        if ($currentDir.exclusions.Count -eq 0) {
            Write-Host "  None" -ForegroundColor Gray
        } else {
            $currentDir.exclusions | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        }
        
        # Get new exclusions
        Write-Host "`nEnter new exclusion patterns (subdirectory names to exclude):" -ForegroundColor Cyan
        Write-Host "Leave blank and press Enter when done" -ForegroundColor Gray
        
        $newExclusions = @()
        $exclusionIndex = 1
        
        while ($true) {
            $exclusion = Read-Host "Exclusion $exclusionIndex (or Enter to finish)"
            if ([string]::IsNullOrWhiteSpace($exclusion)) {
                break
            }
            $newExclusions += $exclusion.Trim()
            $exclusionIndex++
        }
        
        Write-LogDebug -LogPath $LogPath -Message "Collected new exclusions for '$directoryPath': $($newExclusions.Count) items"
        
        # Confirm modification
        Write-Host "`nModifying monitored directory: $directoryPath" -ForegroundColor Green
        Write-Host "  Current exclusions: $($currentDir.exclusions.Count) items" -ForegroundColor Gray
        Write-Host "  New exclusions: $($newExclusions.Count) items" -ForegroundColor Gray
        if ($newExclusions.Count -gt 0) {
            $newExclusions | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        }
        
        $confirm = Read-Host "Confirm? [Y/N]"
        
        if ($confirm -match '^[Yy]') {
            if ($PSCmdlet.ShouldProcess("Monitored directory '$directoryPath'", "Update exclusions from $($currentDir.exclusions.Count) to $($newExclusions.Count) items")) {
                $updatedSettings = Set-MonitoredDirectory -Path $directoryPath -Exclusions $newExclusions -SettingsPath $SettingsPath -LogPath $LogPath
                Write-Host "Monitored directory modified successfully!" -ForegroundColor Green
                Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory modification completed successfully: '$directoryPath' exclusions changed from $($currentDir.exclusions.Count) to $($newExclusions.Count) items"
                
                Read-Host "`nPress Enter to continue"
                return $updatedSettings
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-LogInfo -LogPath $LogPath -Message "Interactive monitored directory modification cancelled by user"
            
            Read-Host "`nPress Enter to continue"
            return $null
        }
    }
    catch {
        Write-LogError -LogPath $LogPath -Message "Failed to modify monitored directory interactively" -Exception $_.Exception
        Write-Host "Error modifying monitored directory: $($_.Exception.Message)" -ForegroundColor Red
        
        Read-Host "`nPress Enter to continue"
        throw
    }
}

# Export all public functions
Export-ModuleMember -Function Read-SettingsFile, New-SettingsFile, Set-StagingArea, Add-DriveMapping, Remove-DriveMapping, Set-DriveMapping, Add-MonitoredDirectory, Remove-MonitoredDirectory, Set-MonitoredDirectory, Show-MultiSelectMenu, Add-DriveMappingInteractive, Remove-DriveMappingInteractive, Set-DriveMappingInteractive, Add-MonitoredDirectoryInteractive, Remove-MonitoredDirectoryInteractive, Set-MonitoredDirectoryInteractive