# AaTurpin.PSConfig

PowerShell module for managing JSON configuration files with drive mappings, monitored directories, and staging area settings. Provides thread-safe configuration management with validation, performance optimizations, comprehensive error handling, plus interactive multi-select menus and interactive configuration functions for user-driven configuration scenarios.

## Features

- **JSON Configuration Management**: Read, create, and modify JSON-based configuration files
- **Drive Mapping Management**: Add, remove, and modify network drive mappings
- **Directory Monitoring**: Configure directories for monitoring with exclusion support
- **Pre-compiled Exclusion Patterns**: Automatic regex compilation for high-performance file filtering
- **Staging Area Configuration**: Set and manage staging area paths
- **Interactive Multi-Select Menus**: Console-based interactive menus for enhanced user experience
- **Interactive Configuration Functions**: User-friendly guided workflows for configuration management
- **Thread-Safe Logging**: Integrated with AaTurpin.PSLogger for comprehensive logging
- **Input Validation**: Robust validation for all configuration parameters
- **Error Handling**: Comprehensive exception handling with detailed logging
- **Memory Management**: Automatic cleanup of compiled patterns on errors
- **PowerShell Standards**: Full support for `-WhatIf`, `-Confirm`, and proper error handling

## Installation

First, register the NuGet repository if you haven't already:

```powershell
Register-PSRepository -Name "NuGet" -SourceLocation "https://api.nuget.org/v3/index.json" -PublishLocation "https://www.nuget.org/api/v2/package/" -InstallationPolicy Trusted
```

Then install the module:

```powershell
Install-Module -Name AaTurpin.PSConfig -Repository NuGet -Scope CurrentUser
```

Or for all users (requires administrator privileges):

```powershell
Install-Module -Name AaTurpin.PSConfig -Repository NuGet -Scope AllUsers
```

## Requirements

- **PowerShell**: 5.1 or later
- **Dependencies**: AaTurpin.PSLogger (automatically installed)

## Quick Start

### Basic Configuration Management

```powershell
# Import the module
Import-Module AaTurpin.PSConfig

# Create a new configuration file with defaults
$config = New-SettingsFile -LogPath "C:\Logs\config.log"

# Read an existing configuration (with automatic performance optimization)
$config = Read-SettingsFile -LogPath "C:\Logs\config.log"

# Set the staging area
Set-StagingArea -StagingAreaPath "D:\MyStaging" -LogPath "C:\Logs\config.log"

# Add a drive mapping
Add-DriveMapping -Letter "X" -Path "\\server\share" -LogPath "C:\Logs\config.log"

# Add a monitored directory with exclusions (automatically compiled for performance)
Add-MonitoredDirectory -Path "V:\aeapps\tools" -Exclusions @("temp", "logs") -LogPath "C:\Logs\config.log"
```

### Interactive Configuration Management

```powershell
# Interactive drive mapping management
$updatedConfig = Add-DriveMappingInteractive -LogPath "C:\Logs\config.log"

# Interactive monitored directory setup
$config = Add-MonitoredDirectoryInteractive -LogPath "C:\Logs\config.log"

# Interactive menu selection
$options = @("Option 1", "Option 2", "Option 3")
$selected = Show-MultiSelectMenu -Title "Select Configuration Items" -Options $options
Write-Host "You selected: $($selected -join ', ')"
```

## Configuration File Structure

The module manages JSON configuration files with the following structure:

```json
{
  "stagingArea": "C:\\StagingArea",
  "driveMappings": [
    {
      "letter": "V",
      "path": "\\\\server\\eng_apps"
    }
  ],
  "monitoredDirectories": [
    {
      "path": "V:\\aeapps\\tools",
      "exclusions": ["temp", "logs", "cache"]
    }
  ]
}
```

**Note**: The module automatically adds compiled regex patterns internally for performance optimization during file operations while preserving the original exclusions for configuration management.

## Performance Optimizations

### Pre-compiled Exclusion Patterns

Version 1.1.0 introduces automatic pre-compilation of exclusion patterns:

- **Regex Compilation**: Exclusion strings are automatically compiled into regex patterns when settings are loaded
- **Performance Boost**: Significantly faster file filtering during directory monitoring operations
- **Memory Management**: Automatic cleanup of compiled patterns on errors
- **Backward Compatibility**: Original exclusion strings are preserved for configuration management
- **Error Handling**: Invalid patterns are logged and skipped, ensuring robust operation

```powershell
# When you load settings, exclusions are automatically optimized
$config = Read-SettingsFile -LogPath "C:\Logs\app.log"

# The config now contains both original exclusions and compiled patterns:
# - $config.monitoredDirectories[0].exclusions (original strings)
# - $config.monitoredDirectories[0].compiledExclusionPatterns (compiled regex objects)
```

## Available Commands

### Configuration File Management

#### `Read-SettingsFile`
Reads, validates, and optimizes a JSON configuration file.

```powershell
$config = Read-SettingsFile -SettingsPath "config.json" -LogPath "C:\Logs\app.log"
```

**Parameters:**
- `SettingsPath` (optional): Path to settings.json file (defaults to "settings.json")
- `LogPath` (required): Path to log file for operations

**New in v1.1.0**: Automatically pre-compiles exclusion patterns for enhanced performance during file system operations.

#### `New-SettingsFile`
Creates a new configuration file with default values.

```powershell
$config = New-SettingsFile -SettingsPath "config.json" -LogPath "C:\Logs\app.log" -StagingArea "D:\Staging"
```

**Parameters:**
- `SettingsPath` (optional): Path for new settings file (defaults to "settings.json")
- `LogPath` (required): Path to log file
- `StagingArea` (optional): Custom staging area path (defaults to "C:\StagingArea")

### Staging Area Management

#### `Set-StagingArea`
Updates the staging area path in the configuration.

```powershell
Set-StagingArea -StagingAreaPath "E:\NewStaging" -LogPath "C:\Logs\app.log"
```

**Parameters:**
- `StagingAreaPath` (required): New staging area path
- `SettingsPath` (optional): Path to settings file
- `LogPath` (required): Path to log file

### Drive Mapping Management

#### `Add-DriveMapping`
Adds a new network drive mapping.

```powershell
Add-DriveMapping -Letter "Y" -Path "\\nas\data" -LogPath "C:\Logs\app.log"
```

**Parameters:**
- `Letter` (required): Single alphabetic character for drive letter
- `Path` (required): UNC path (must start with \\)
- `SettingsPath` (optional): Path to settings file
- `LogPath` (required): Path to log file

#### `Remove-DriveMapping`
Removes an existing drive mapping.

```powershell
Remove-DriveMapping -Letter "Y" -LogPath "C:\Logs\app.log"
```

#### `Set-DriveMapping`
Modifies the path of an existing drive mapping.

```powershell
Set-DriveMapping -Letter "Y" -Path "\\newserver\data" -LogPath "C:\Logs\app.log"
```

### Interactive Drive Mapping Management

**New in v1.3.0**: Interactive functions provide guided workflows for drive mapping management.

#### `Add-DriveMappingInteractive`
Interactively adds a new drive mapping with guided prompts.

```powershell
$config = Add-DriveMappingInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Guided prompts for drive letter and UNC path
- Input validation with retry on invalid entries
- Confirmation before making changes
- Support for `-WhatIf` and `-Confirm` parameters
- Returns updated configuration object or `$null` if cancelled

#### `Remove-DriveMappingInteractive`
Interactively removes an existing drive mapping with menu selection.

```powershell
$config = Remove-DriveMappingInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Visual menu showing all current drive mappings
- Interactive selection using arrow keys or number input
- Confirmation prompt before deletion
- Handles cases with no mappings gracefully

#### `Set-DriveMappingInteractive`
Interactively modifies an existing drive mapping.

```powershell
$config = Set-DriveMappingInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Menu selection of existing mappings
- Shows current path and prompts for new path
- Input validation for UNC paths
- Before/after display for clarity

### Monitored Directory Management

#### `Add-MonitoredDirectory`
Adds a directory to the monitoring configuration.

```powershell
Add-MonitoredDirectory -Path "V:\aeapps\newtools" -Exclusions @("temp", "cache") -LogPath "C:\Logs\app.log"
```

**Parameters:**
- `Path` (required): Directory path to monitor
- `Exclusions` (optional): Array of subdirectory names to exclude
- `SettingsPath` (optional): Path to settings file
- `LogPath` (required): Path to log file

#### `Remove-MonitoredDirectory`
Removes a directory from monitoring configuration.

```powershell
Remove-MonitoredDirectory -Path "V:\aeapps\oldtools" -LogPath "C:\Logs\app.log"
```

#### `Set-MonitoredDirectory`
Updates the exclusions list for a monitored directory.

```powershell
Set-MonitoredDirectory -Path "V:\aeapps\tools" -Exclusions @("logs", "temp", "backup") -LogPath "C:\Logs\app.log"
```

### Interactive Monitored Directory Management

**New in v1.3.0**: Interactive functions for user-friendly directory monitoring configuration.

#### `Add-MonitoredDirectoryInteractive`
Interactively adds a new monitored directory with guided exclusion setup.

```powershell
$config = Add-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Guided prompts for directory path
- Step-by-step exclusion pattern entry
- Visual summary before confirmation
- Handles empty exclusion lists gracefully

#### `Remove-MonitoredDirectoryInteractive`
Interactively removes a monitored directory with menu selection.

```powershell
$config = Remove-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Visual menu showing directories with exclusion counts
- Safe removal with confirmation prompts
- Handles empty directory lists

#### `Set-MonitoredDirectoryInteractive`
Interactively modifies exclusions for an existing monitored directory.

```powershell
$config = Set-MonitoredDirectoryInteractive -LogPath "C:\Logs\app.log"
```

**Features:**
- Menu selection of existing directories
- Shows current exclusions before modification
- Step-by-step entry of new exclusions
- Visual before/after comparison

### Interactive User Interface

#### `Show-MultiSelectMenu`
**Enhanced in v1.2.0**: Displays an interactive multi-select menu in the PowerShell console.

```powershell
$services = Get-Service | Select-Object -First 5 -ExpandProperty Name
$selectedServices = Show-MultiSelectMenu -Title "Select Services" -Options $services
```

**Parameters:**
- `Title` (required): The title to display at the top of the menu
- `Options` (required): Array of menu options to display
- `AllowEmpty` (optional): Whether to allow confirming with no selections (default: $false)
- `ShowInstructions` (optional): Whether to show navigation instructions (default: $true)

**Features:**
- **Arrow Key Navigation**: Use Up/Down arrows or k/j keys to navigate (when supported)
- **Space to Select**: Toggle selection with spacebar
- **Batch Operations**: Select all (a) or clear all (c)
- **Fallback Mode**: Automatic fallback to number-based input for environments without enhanced keyboard support
- **Visual Feedback**: Clear indication of selected items with [X] and current position
- **Flexible Input**: Supports both enhanced console environments and basic text input

**Navigation:**
- **Enhanced Mode** (regular PowerShell console):
  - `Up/Down` or `k/j`: Navigate
  - `Space`: Toggle selection
  - `Enter`: Confirm selection
  - `Esc` or `q`: Cancel
  - `a`: Select all
  - `c`: Clear all
  - `Home/End`: Jump to first/last item

- **Fallback Mode** (ISE, limited environments):
  - `1-N`: Toggle item by number
  - `a`: Select all
  - `c`: Clear all
  - `Enter`: Confirm selection
  - `q`: Cancel

**Returns:**
Array of selected option strings

### Configuration Reporting

#### `Show-Settings`
**New in v1.3.0**: Displays comprehensive configuration information with system status.

```powershell
# Basic configuration overview
Show-Settings -LogPath "C:\Logs\app.log"

# Detailed report with system status and accessibility checks
Show-Settings -SettingsPath "config.json" -LogPath "C:\Logs\app.log" -ShowDetails
```

**Parameters:**
- `SettingsPath` (optional): Path to settings.json file (defaults to "settings.json")
- `LogPath` (required): Path to log file for operations
- `ShowDetails` (optional): Switch to enable detailed reporting mode

**Features:**
- **Configuration File Information**: Location, last modified date, and file size
- **Staging Area Status**: Path validation and accessibility checking
- **Drive Mapping Status**: Shows mapping status with ✓/✗ indicators
- **Directory Monitoring Status**: Accessibility checks for all monitored directories
- **Performance Optimization Display**: Shows compiled regex pattern counts
- **Visual Status Indicators**: Color-coded status with checkmarks and warnings
- **System Health Summary**: Overall configuration health assessment

**Detailed Mode Features** (with `-ShowDetails`):
- **File Enumeration**: Fast .NET-based file and directory counting in staging areas
- **Size Calculations**: Total size of files with smart unit formatting (bytes/KB/MB/GB)
- **Network Path Testing**: Accessibility testing for all UNC and local paths
- **Drive Mapping Verification**: Validates actual vs. configured drive mappings
- **Exclusion Pattern Details**: Shows all exclusion patterns and compilation status
- **Comprehensive Statistics**: Detailed breakdown of accessible vs. inaccessible resources

**Example Output:**
```
Configuration Report
==================================================

Configuration File:
  Location: C:\Config\settings.json
  Last Modified: 2025-07-06 14:30:22
  Size: 2.48 KB

Staging Area:
  Path: D:\StagingArea
  Status: ✓ Exists
  Created: 2025-07-05 09:15:33
  Contents: 1,247 items (1,089 files, 158 directories)
  Total Size: 45.7 MB

Drive Mappings: 3
  V: -> \\server\eng_apps
    Status: ✓ Mapped
    Network Path: ✓ Accessible
  X: -> \\nas\data
    Status: ✗ Not Mapped
    Network Path: ✗ Not Accessible
  T: -> \\backup\archive
    Status: ✓ Mapped
    Network Path: ✓ Accessible

Monitored Directories: 5
  Total Exclusion Patterns: 12 (compiled: 12)

  V:\aeapps\tools
    Exclusions: 3 patterns (3 compiled)
    Status: ✓ Accessible
    Exclusion Patterns:
      - temp
      - logs
      - cache

Summary:
  Configuration Status: Valid
  Drive Mappings: 2/3 accessible
  Monitored Directories: 4/5 accessible
  Regex Patterns: 12/12 compiled successfully
```

**Performance Benefits:**
- **Fast File Counting**: Uses .NET `DirectoryInfo` methods instead of PowerShell cmdlets
- **Efficient Path Testing**: Batch accessibility testing with minimal overhead
- **Smart Caching**: Avoids redundant file system calls during reporting
- **Memory Efficient**: No PowerShell pipeline overhead for large directory structures

**Administrative Value:**
- **Quick Health Checks**: Instant visual overview of configuration status
- **Troubleshooting Aid**: Identifies inaccessible paths and configuration issues
- **Audit Support**: Comprehensive logging of all status checks and findings
- **Capacity Planning**: File counts and sizes for staging area management

## Examples

### Interactive Configuration Workflow

```powershell
# Complete interactive configuration setup
Import-Module AaTurpin.PSConfig

$logPath = "C:\Logs\config-setup.log"

# Create base configuration
Write-Host "Setting up new configuration..." -ForegroundColor Cyan
$config = New-SettingsFile -LogPath $logPath

# Interactive drive mapping setup
Write-Host "`nSetting up drive mappings..." -ForegroundColor Cyan
do {
    $config = Add-DriveMappingInteractive -LogPath $logPath
    $response = Read-Host "`nAdd another drive mapping? [Y/N]"
} while ($response -match '^[Yy]' -and $config)

# Interactive directory monitoring setup
Write-Host "`nSetting up monitored directories..." -ForegroundColor Cyan
do {
    $config = Add-MonitoredDirectoryInteractive -LogPath $logPath
    $response = Read-Host "`nAdd another monitored directory? [Y/N]"
} while ($response -match '^[Yy]' -and $config)

Write-Host "`n✓ Interactive configuration setup completed!" -ForegroundColor Green
```

### Configuration Management Menu System

```powershell
function Show-ConfigurationMenu {
    param([string]$LogPath = "C:\Logs\config.log")
    
    while ($true) {
        # Show current configuration status
        try {
            $config = Read-SettingsFile -LogPath $LogPath
            Write-Host "`nCurrent Configuration:" -ForegroundColor Cyan
            Write-Host "  Staging Area: $($config.stagingArea)" -ForegroundColor White
            Write-Host "  Drive Mappings: $($config.driveMappings.Count)" -ForegroundColor White
            Write-Host "  Monitored Directories: $($config.monitoredDirectories.Count)" -ForegroundColor White
        }
        catch {
            Write-Host "`nNo configuration file found." -ForegroundColor Yellow
        }
        
        # Main menu options
        $menuOptions = @(
            "Manage Drive Mappings",
            "Manage Monitored Directories",
            "Set Staging Area",
            "View Full Configuration",
            "Exit"
        )
        
        $selection = Show-MultiSelectMenu -Title "Configuration Management" -Options $menuOptions -AllowEmpty $false
        
        switch ($selection[0]) {
            "Manage Drive Mappings" {
                Show-DriveManagementMenu -LogPath $LogPath
            }
            "Manage Monitored Directories" {
                Show-DirectoryManagementMenu -LogPath $LogPath
            }
            "Set Staging Area" {
                $newPath = Read-Host "Enter new staging area path"
                Set-StagingArea -StagingAreaPath $newPath -LogPath $LogPath
                Write-Host "✓ Staging area updated" -ForegroundColor Green
            }
            "View Full Configuration" {
                $config = Read-SettingsFile -LogPath $LogPath
                $config | ConvertTo-Json -Depth 3 | Write-Host
            }
            "Exit" {
                return
            }
        }
    }
}

function Show-DriveManagementMenu {
    param([string]$LogPath)
    
    $driveOptions = @(
        "Add Drive Mapping",
        "Remove Drive Mapping", 
        "Modify Drive Mapping",
        "Back to Main Menu"
    )
    
    $selection = Show-MultiSelectMenu -Title "Drive Mapping Management" -Options $driveOptions -AllowEmpty $false
    
    switch ($selection[0]) {
        "Add Drive Mapping" { Add-DriveMappingInteractive -LogPath $LogPath }
        "Remove Drive Mapping" { Remove-DriveMappingInteractive -LogPath $LogPath }
        "Modify Drive Mapping" { Set-DriveMappingInteractive -LogPath $LogPath }
        "Back to Main Menu" { return }
    }
}

function Show-DirectoryManagementMenu {
    param([string]$LogPath)
    
    $directoryOptions = @(
        "Add Monitored Directory",
        "Remove Monitored Directory",
        "Modify Directory Exclusions",
        "Back to Main Menu"
    )
    
    $selection = Show-MultiSelectMenu -Title "Directory Management" -Options $directoryOptions -AllowEmpty $false
    
    switch ($selection[0]) {
        "Add Monitored Directory" { Add-MonitoredDirectoryInteractive -LogPath $LogPath }
        "Remove Monitored Directory" { Remove-MonitoredDirectoryInteractive -LogPath $LogPath }
        "Modify Directory Exclusions" { Set-MonitoredDirectoryInteractive -LogPath $LogPath }
        "Back to Main Menu" { return }
    }
}

# Start the interactive configuration system
Show-ConfigurationMenu
```

### Programmatic Configuration with Interactive Fallback

```powershell
# Automated configuration with interactive fallback
Import-Module AaTurpin.PSConfig

$logPath = "C:\Logs\hybrid-config.log"

# Try to read existing configuration
try {
    $config = Read-SettingsFile -LogPath $logPath
    Write-Host "✓ Existing configuration loaded" -ForegroundColor Green
}
catch {
    Write-Host "No existing configuration found. Creating new one..." -ForegroundColor Yellow
    $config = New-SettingsFile -LogPath $logPath
}

# Programmatically add required drive mappings
$requiredMappings = @(
    @{ Letter = "V"; Path = "\\server\eng_apps" },
    @{ Letter = "W"; Path = "\\nas\shared_data" }
)

foreach ($mapping in $requiredMappings) {
    try {
        Add-DriveMapping -Letter $mapping.Letter -Path $mapping.Path -LogPath $logPath
        Write-Host "✓ Added drive mapping: $($mapping.Letter) -> $($mapping.Path)" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to add drive mapping: $($mapping.Letter)" -ForegroundColor Red
        Write-Host "Would you like to add it manually?" -ForegroundColor Yellow
        $response = Read-Host "[Y/N]"
        if ($response -match '^[Yy]') {
            Add-DriveMappingInteractive -LogPath $logPath
        }
    }
}

# Interactive setup for optional directories
Write-Host "`nOptional: Add monitored directories interactively" -ForegroundColor Cyan
$response = Read-Host "Would you like to add monitored directories? [Y/N]"
while ($response -match '^[Yy]') {
    $config = Add-MonitoredDirectoryInteractive -LogPath $logPath
    $response = Read-Host "Add another? [Y/N]"
}

Write-Host "✓ Configuration setup completed!" -ForegroundColor Green
```

### Advanced Interactive Features

```powershell
# Advanced menu with dynamic options
function Show-AdvancedConfigMenu {
    $logPath = "C:\Logs\advanced-config.log"
    
    # Load current configuration
    try {
        $config = Read-SettingsFile -LogPath $logPath
    }
    catch {
        Write-Host "Creating new configuration file..." -ForegroundColor Yellow
        $config = New-SettingsFile -LogPath $logPath
    }
    
    # Dynamic menu based on current state
    $menuOptions = @()
    
    if ($config.driveMappings.Count -eq 0) {
        $menuOptions += "🔧 Add First Drive Mapping"
    } else {
        $menuOptions += "📁 Manage Drive Mappings ($($config.driveMappings.Count) configured)"
    }
    
    if ($config.monitoredDirectories.Count -eq 0) {
        $menuOptions += "📂 Add First Monitored Directory"
    } else {
        $menuOptions += "👁‍🗨 Manage Monitored Directories ($($config.monitoredDirectories.Count) configured)"
    }
    
    $menuOptions += "⚙️ Advanced Settings"
    $menuOptions += "💾 Export Configuration"
    $menuOptions += "❌ Exit"
    
    $selection = Show-MultiSelectMenu -Title "Advanced Configuration Manager" -Options $menuOptions -ShowInstructions $false
    
    Write-Host "Selected: $($selection[0])" -ForegroundColor Green
}

# Show configuration with status indicators
function Show-ConfigurationStatus {
    $logPath = "C:\Logs\status.log"
    
    try {
        $config = Read-SettingsFile -LogPath $logPath
        
        Write-Host "`n📊 Configuration Status Report" -ForegroundColor Cyan
        Write-Host "=" * 35 -ForegroundColor Cyan
        
        # Staging area status
        $stagingExists = Test-Path $config.stagingArea
        $stagingIcon = if ($stagingExists) { "✅" } else { "❌" }
        Write-Host "$stagingIcon Staging Area: $($config.stagingArea)" -ForegroundColor $(if ($stagingExists) { "Green" } else { "Red" })
        
        # Drive mappings status
        Write-Host "`n📁 Drive Mappings:" -ForegroundColor Yellow
        if ($config.driveMappings.Count -eq 0) {
            Write-Host "  No drive mappings configured" -ForegroundColor Gray
        } else {
            foreach ($mapping in $config.driveMappings) {
                $driveExists = Test-Path "$($mapping.letter):"
                $driveIcon = if ($driveExists) { "✅" } else { "❌" }
                Write-Host "  $driveIcon $($mapping.letter): -> $($mapping.path)" -ForegroundColor $(if ($driveExists) { "Green" } else { "Red" })
            }
        }
        
        # Monitored directories status
        Write-Host "`n👁‍🗨 Monitored Directories:" -ForegroundColor Yellow
        if ($config.monitoredDirectories.Count -eq 0) {
            Write-Host "  No monitored directories configured" -ForegroundColor Gray
        } else {
            foreach ($directory in $config.monitoredDirectories) {
                $dirExists = Test-Path $directory.path
                $dirIcon = if ($dirExists) { "✅" } else { "❌" }
                $exclusionCount = $directory.exclusions.Count
                $compiledCount = $directory.compiledExclusionPatterns.Count
                Write-Host "  $dirIcon $($directory.path)" -ForegroundColor $(if ($dirExists) { "Green" } else { "Red" })
                Write-Host "    Exclusions: $exclusionCount patterns, $compiledCount compiled" -ForegroundColor Gray
            }
        }
        
        # Performance summary
        $totalPatterns = ($config.monitoredDirectories | ForEach-Object { $_.compiledExclusionPatterns.Count } | Measure-Object -Sum).Sum
        Write-Host "`n⚡ Performance: $totalPatterns compiled exclusion patterns ready" -ForegroundColor Cyan
        
    }
    catch {
        Write-Host "❌ No configuration file found or error reading configuration" -ForegroundColor Red
        Write-Host "Run New-SettingsFile to create a new configuration" -ForegroundColor Yellow
    }
}

# Usage
Show-ConfigurationStatus
Show-AdvancedConfigMenu
```

### Working with Compiled Patterns

```powershell
# Load configuration with compiled patterns
$config = Read-SettingsFile -LogPath "C:\Logs\app.log"

# Example: Use compiled patterns for high-performance filtering
foreach ($directory in $config.monitoredDirectories) {
    Write-Host "Directory: $($directory.path)"
    Write-Host "  Original exclusions: $($directory.exclusions -join ', ')"
    Write-Host "  Compiled patterns: $($directory.compiledExclusionPatterns.Count)"
    
    # The compiled patterns can be used directly for fast path matching
    # Example usage in file system operations:
    $testPaths = @("temp\subfolder", "logs\debug", "cache\images", "normal\folder")
    
    foreach ($testPath in $testPaths) {
        $shouldExclude = $directory.compiledExclusionPatterns | Where-Object { $_.IsMatch($testPath.ToLowerInvariant()) }
        $status = if ($shouldExclude) { "EXCLUDED" } else { "INCLUDED" }
        $color = if ($shouldExclude) { "Yellow" } else { "Green" }
        Write-Host "    Path '$testPath': $status" -ForegroundColor $color
    }
}
```

## PowerShell Standards Compliance

All interactive functions support standard PowerShell features:

### WhatIf and Confirm Support

```powershell
# Test what would happen without making changes
Add-DriveMappingInteractive -LogPath "C:\Logs\app.log" -WhatIf

# Require confirmation for each operation
Remove-DriveMappingInteractive -LogPath "C:\Logs\app.log" -Confirm

# Combine with confirmation preference
$ConfirmPreference = "High"
Set-DriveMappingInteractive -LogPath "C:\Logs\app.log"
```

### Error Handling and Return Values

```powershell
# All interactive functions return the updated configuration object or $null
try {
    $updatedConfig = Add-DriveMappingInteractive -LogPath "C:\Logs\app.log"
    if ($updatedConfig) {
        Write-Host "✓ Configuration updated successfully"
        Write-Host "Drive mappings: $($updatedConfig.driveMappings.Count)"
    } else {
        Write-Host "Operation was cancelled by user"
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    # Handle error appropriately
}
```

### Pipeline Integration

```powershell
# Interactive functions can be chained
$config = New-SettingsFile -LogPath $logPath |
    Add-DriveMappingInteractive -LogPath $logPath |
    Add-MonitoredDirectoryInteractive -LogPath $logPath

if ($config) {
    Write-Host "✓ Complete configuration setup finished"
}
```

### Configuration Status and Reporting Examples

```powershell
# Quick configuration health check
Import-Module AaTurpin.PSConfig
Show-Settings -LogPath "C:\Logs\config-check.log"

# Comprehensive system status report
Show-Settings -LogPath "C:\Logs\detailed-report.log" -ShowDetails

# Integration with configuration management workflow
function Invoke-ConfigurationHealthCheck {
    param([string]$ConfigPath = "settings.json")
    
    $logPath = "C:\Logs\health-check-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    
    Write-Host "Performing configuration health check..." -ForegroundColor Cyan
    
    try {
        # Generate detailed status report
        Show-Settings -SettingsPath $ConfigPath -LogPath $logPath -ShowDetails
        
        # Additional validation
        $config = Read-SettingsFile -SettingsPath $ConfigPath -LogPath $logPath
        
        # Check for common issues
        $issues = @()
        
        # Check staging area accessibility
        if (-not (Test-Path $config.stagingArea)) {
            $issues += "Staging area not accessible: $($config.stagingArea)"
        }
        
        # Check drive mappings
        foreach ($mapping in $config.driveMappings) {
            if (-not (Test-Path "$($mapping.letter):\")) {
                $issues += "Drive $($mapping.letter): not mapped"
            }
        }
        
        # Check monitored directories
        foreach ($directory in $config.monitoredDirectories) {
            if (-not (Test-Path $directory.path)) {
                $issues += "Monitored directory not accessible: $($directory.path)"
            }
        }
        
        # Report issues
        if ($issues.Count -gt 0) {
            Write-Host "`n⚠️  Issues Found:" -ForegroundColor Yellow
            $issues | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
            return $false
        } else {
            Write-Host "`n✅ Configuration health check passed!" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "`n❌ Configuration health check failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Automated monitoring script
function Start-ConfigurationMonitoring {
    param(
        [int]$IntervalMinutes = 30,
        [string]$ConfigPath = "settings.json",
        [string]$LogPath = "C:\Logs\config-monitor.log"
    )
    
    Write-Host "Starting configuration monitoring (every $IntervalMinutes minutes)..." -ForegroundColor Cyan
    
    while ($true) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "`n[$timestamp] Running configuration check..." -ForegroundColor Gray
        
        try {
            # Quick status check (no details to reduce log noise)
            Show-Settings -SettingsPath $ConfigPath -LogPath $LogPath
            Write-Host "✓ Configuration check completed" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Configuration check failed: $($_.Exception.Message)" -ForegroundColor Red
            # Could send alert/notification here
        }
        
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}

# Usage examples
Invoke-ConfigurationHealthCheck
Start-ConfigurationMonitoring -IntervalMinutes 15
```

### Integration with Existing Helper Functions

```powershell
# Update your helpers.ps1 to use Show-Settings instead of Show-Configuration

function Initialize-System {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    Write-Host "Starting Network Share Snapshot Manager..." -ForegroundColor Cyan
    
    # Load modules and initialize logging
    Write-LogInfo -LogPath $LogPath -Message "=== Network Share Snapshot Manager Started ==="
    Write-Host "✓ Logging initialized: $LogPath" -ForegroundColor Green
    
    # Initialize configuration with enhanced reporting
    Show-Settings -SettingsPath $SettingsPath -LogPath $LogPath -ShowDetails
    Initialize-DriveMappings -SettingsPath $SettingsPath -LogPath $LogPath
    
    Write-Host "`nSystem initialization completed successfully!" -ForegroundColor Green
    Write-LogInfo -LogPath $LogPath -Message "System ready for snapshot operations"
}
```

## Validation and Error Handling

The module includes comprehensive validation:

- **Drive Letters**: Must be single alphabetic characters
- **UNC Paths**: Must start with `\\` and be properly formatted
- **Uniqueness**: Drive letters and monitored directory paths must be unique
- **JSON Structure**: Automatic validation and repair of configuration structure
- **Regex Compilation**: Invalid exclusion patterns are logged and skipped
- **File Operations**: Thread-safe file operations with retry logic
- **Memory Management**: Automatic cleanup of compiled patterns on errors
- **Menu Input**: Robust input validation for interactive menus with fallback support
- **Interactive Input**: Real-time validation with retry prompts for invalid entries

All operations are logged using the AaTurpin.PSLogger module for complete audit trails.

## Thread Safety

The module integrates with AaTurpin.PSLogger to provide thread-safe file operations, making it suitable for:

- Multi-threaded applications
- Concurrent PowerShell sessions
- Automated scripts running simultaneously
- Enterprise environments with shared configuration files

## Version History

### Version 1.3.0
- **New**: Interactive configuration functions for user-friendly management
- **Feature**: `Add-DriveMappingInteractive`, `Remove-DriveMappingInteractive`, `Set-DriveMappingInteractive`
- **Feature**: `Add-MonitoredDirectoryInteractive`, `Remove-MonitoredDirectoryInteractive`, `Set-MonitoredDirectoryInteractive`
- **Enhancement**: Full PowerShell standards compliance with `-WhatIf` and `-Confirm` support
- **Enhancement**: Consistent return values and error handling patterns
- **Enhancement**: Comprehensive help documentation for all new functions
- **Compatibility**: Maintains full backward compatibility with all existing functionality

### Version 1.2.0
- **New**: `Show-MultiSelectMenu` function for interactive user selection scenarios
- **Feature**: Console-based multi-select menus with arrow key navigation
- **Feature**: Automatic fallback input method for environments without enhanced keyboard support
- **Enhancement**: Perfect for configuration management workflows requiring user interaction
- **Compatibility**: Maintains full backward compatibility with all existing functionality

### Version 1.1.0
- **New**: Pre-compiled regex patterns for exclusions
- **Enhancement**: Significant performance improvement for file filtering operations
- **Enhancement**: Automatic memory management and cleanup
- **Enhancement**: Improved error handling for invalid regex patterns
- **Improvement**: Enhanced logging with pattern compilation details

### Version 1.0.0
- Initial release with core configuration management functionality
- Drive mapping management
- Monitored directory configuration
- Thread-safe logging integration

## License

MIT License - see [LICENSE](https://github.com/aturpin0504/AaTurpin.PSConfig?tab=MIT-1-ov-file) for details.

## Project Links

- **GitHub Repository**: [https://github.com/aturpin0504/AaTurpin.PSConfig](https://github.com/aturpin0504/AaTurpin.PSConfig)
- **PowerShell Gallery**: [AaTurpin.PSConfig](https://www.powershellgallery.com/packages/AaTurpin.PSConfig)
- **Dependencies**: [AaTurpin.PSLogger](https://www.powershellgallery.com/packages/AaTurpin.PSLogger)

## Support

For issues, feature requests, or contributions, please visit the [GitHub repository](https://github.com/aturpin0504/AaTurpin.PSConfig).