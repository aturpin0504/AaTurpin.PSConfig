function Read-SettingsFile {
    <#
    .SYNOPSIS
        Reads application settings from a JSON configuration file with compiled exclusion patterns.
    
    .DESCRIPTION
        Parses a JSON settings file and returns the configuration as a PowerShell object.
        Uses the LoggingModule for operation logging. Includes enhanced error handling
        and validation for robust operation. Automatically pre-compiles regex patterns for exclusions.
    
    .PARAMETER SettingsPath
        The path to the settings.json file. Defaults to "settings.json" in the current directory.
    
    .PARAMETER LogPath
        The path to the log file for recording operations.
    
    .OUTPUTS
        PSCustomObject containing the parsed settings with compiled exclusion patterns for monitored directories.
    
    .EXAMPLE
        $settings = Read-SettingsFile -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"
        Write-Host "Staging Area: $($settings.stagingArea)"
        Write-Host "Found $($settings.monitoredDirectories.Count) directories"
        # Access compiled patterns: $settings.monitoredDirectories[0].compiledExclusionPatterns
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = "settings.json",
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    try {
        Write-LogInfo -LogPath $LogPath -Message "Reading settings file: $SettingsPath with exclusion pattern compilation"
        
        # Check if settings file exists
        if (-not (Test-Path -Path $SettingsPath)) {
            $errorMsg = "Settings file not found: $SettingsPath"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Check if file is empty
        $fileInfo = Get-Item -Path $SettingsPath
        if ($fileInfo.Length -eq 0) {
            $errorMsg = "Settings file is empty: $SettingsPath"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Read and parse JSON file
        try {
            $jsonContent = Get-Content -Path $SettingsPath -Raw -ErrorAction Stop
            
            # Check if content is empty or whitespace only
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                $errorMsg = "Settings file contains no valid content: $SettingsPath"
                Write-LogError -LogPath $LogPath -Message $errorMsg
                throw $errorMsg
            }
            
            $settings = $jsonContent | ConvertFrom-Json -ErrorAction Stop
            
            # Ensure we have a valid object (not null)
            if ($null -eq $settings) {
                $errorMsg = "Failed to parse JSON content from settings file: $SettingsPath"
                Write-LogError -LogPath $LogPath -Message $errorMsg
                throw $errorMsg
            }
        }
        catch {
            $errorMsg = "Invalid JSON format in settings file: $($_.Exception.Message)"
            Write-LogError -LogPath $LogPath -Message $errorMsg -Exception $_.Exception
            throw $errorMsg
        }
        
        # Validate and set default values for required properties
        if ([string]::IsNullOrWhiteSpace($settings.stagingArea)) {
            Write-LogWarning -LogPath $LogPath -Message "Property 'stagingArea' is missing or null in settings file, defaulting to 'C:\StagingArea'"
            
            # Check if stagingArea property exists, if not add it
            if (-not ($settings.PSObject.Properties.Name -contains 'stagingArea')) {
                $settings | Add-Member -NotePropertyName 'stagingArea' -NotePropertyValue 'C:\StagingArea' -Force
            }
            else {
                $settings.stagingArea = 'C:\StagingArea'
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($settings.vDrivePath)) {
            $errorMsg = "Required property 'vDrivePath' is missing or null in settings file"
            Write-LogError -LogPath $LogPath -Message $errorMsg
            throw $errorMsg
        }
        
        # Initialize monitoredDirectories if it doesn't exist
        if (-not ($settings.PSObject.Properties.Name -contains 'monitoredDirectories')) {
            Write-LogWarning -LogPath $LogPath -Message "Property 'monitoredDirectories' is missing, initializing as empty array"
            $settings | Add-Member -NotePropertyName 'monitoredDirectories' -NotePropertyValue @() -Force
        }
        
        # Filter out malformed monitored directories and optionally compile exclusion patterns
        $validDirectories = @()
        $skippedCount = 0
        $compiledPatternCount = 0
        
        if ($settings.monitoredDirectories -and $settings.monitoredDirectories -is [Array]) {
            foreach ($directory in $settings.monitoredDirectories) {
                try {
                    # Skip non-object entries (like strings, numbers, etc.)
                    if ($directory -isnot [PSCustomObject] -and $directory -isnot [System.Management.Automation.PSCustomObject]) {
                        Write-LogWarning -LogPath $LogPath -Message "Skipping non-object directory entry: $($directory.GetType().Name)"
                        $skippedCount++
                        continue
                    }
                    
                    # Check if directory has required 'path' property and it's not null/empty
                    if ($directory.PSObject.Properties['path'] -and -not [string]::IsNullOrWhiteSpace($directory.path)) {
                        # Ensure exclusions property exists and is an array
                        if (-not ($directory.PSObject.Properties.Name -contains 'exclusions')) {
                            $directory | Add-Member -NotePropertyName 'exclusions' -NotePropertyValue @() -Force
                        }
                        elseif ($directory.exclusions -isnot [Array]) {
                            # Convert non-array exclusions to array
                            if ($null -eq $directory.exclusions) {
                                $directory.exclusions = @()
                            }
                            else {
                                $directory.exclusions = @($directory.exclusions)
                            }
                        }
                        
                        # Pre-compile exclusion patterns for performance
                        if ($directory.exclusions.Count -gt 0) {
                            try {
                                # Normalize exclusions (same logic as Get-NetworkShareSnapshot)
                                $normalizedExclusions = $directory.exclusions | ForEach-Object {
                                    $_.Trim('\', '/').Replace('/', '\').ToLowerInvariant()
                                }
                                
                                # Create compiled regex patterns for exact matching
                                $exclusionPatterns = $normalizedExclusions | ForEach-Object {
                                    [regex]::new("^$([regex]::Escape($_))($|\\)", 
                                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor 
                                        [System.Text.RegularExpressions.RegexOptions]::Compiled)
                                }
                                
                                # Add compiled patterns to the directory object
                                $directory | Add-Member -NotePropertyName 'compiledExclusionPatterns' -NotePropertyValue $exclusionPatterns -Force
                                $compiledPatternCount += $exclusionPatterns.Count
                                
                                Write-LogDebug -LogPath $LogPath -Message "Compiled $($exclusionPatterns.Count) exclusion patterns for directory: $($directory.path)"
                            }
                            catch {
                                Write-LogWarning -LogPath $LogPath -Message "Failed to compile exclusion patterns for directory '$($directory.path)': $($_.Exception.Message)"
                                # Continue without compiled patterns
                            }
                        }
                        
                        $validDirectories += $directory
                    }
                    else {
                        Write-LogWarning -LogPath $LogPath -Message "Skipping malformed directory entry: missing or empty 'path' property"
                        $skippedCount++
                    }
                }
                catch {
                    Write-LogWarning -LogPath $LogPath -Message "Skipping malformed directory entry: $($_.Exception.Message)"
                    $skippedCount++
                }
            }
        }
        elseif ($settings.monitoredDirectories -and $settings.monitoredDirectories -isnot [Array]) {
            Write-LogWarning -LogPath $LogPath -Message "Property 'monitoredDirectories' is not an array, converting to empty array"
            $validDirectories = @()
            $skippedCount = 1
        }
        
        # Update settings with valid directories only
        $settings.monitoredDirectories = $validDirectories
        
        $logMessage = "Successfully parsed settings file. Valid directories: $($validDirectories.Count), Skipped: $skippedCount, Compiled patterns: $compiledPatternCount"
        Write-LogInfo -LogPath $LogPath -Message $logMessage
        
        return $settings
    }
    catch {
        $errorMsg = "Failed to read or parse settings file: $($_.Exception.Message)"
        Write-LogError -LogPath $LogPath -Message $errorMsg -Exception $_.Exception
        throw
    }
}

Export-ModuleMember -Function Read-SettingsFile