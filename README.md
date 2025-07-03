# AaTurpin.PSConfig

PowerShell module for managing JSON configuration files with drive mappings, monitored directories, and staging area settings. Provides thread-safe configuration management with validation and comprehensive error handling.

## Features

- **JSON Configuration Management**: Read, create, and modify JSON-based configuration files
- **Drive Mapping Management**: Add, remove, and modify network drive mappings
- **Directory Monitoring**: Configure directories for monitoring with exclusion support
- **Staging Area Configuration**: Set and manage staging area paths
- **Thread-Safe Logging**: Integrated with AaTurpin.PSLogger for comprehensive logging
- **Input Validation**: Robust validation for all configuration parameters
- **Error Handling**: Comprehensive exception handling with detailed logging

## Installation

Install from the PowerShell Gallery:

```powershell
Install-Module -Name AaTurpin.PSConfig -Scope CurrentUser
```

Or for all users (requires administrator privileges):

```powershell
Install-Module -Name AaTurpin.PSConfig -Scope AllUsers
```

## Requirements

- **PowerShell**: 5.1 or later
- **Dependencies**: AaTurpin.PSLogger (automatically installed)

## Quick Start

```powershell
# Import the module
Import-Module AaTurpin.PSConfig

# Create a new configuration file with defaults
$config = New-SettingsFile -LogPath "C:\Logs\config.log"

# Read an existing configuration
$config = Read-SettingsFile -LogPath "C:\Logs\config.log"

# Set the staging area
Set-StagingArea -StagingAreaPath "D:\MyStaging" -LogPath "C:\Logs\config.log"

# Add a drive mapping
Add-DriveMapping -Letter "X" -Path "\\server\share" -LogPath "C:\Logs\config.log"

# Add a monitored directory with exclusions
Add-MonitoredDirectory -Path "V:\aeapps\tools" -Exclusions @("temp", "logs") -LogPath "C:\Logs\config.log"
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

## Available Commands

### Configuration File Management

#### `Read-SettingsFile`
Reads and validates a JSON configuration file.

```powershell
$config = Read-SettingsFile -SettingsPath "config.json" -LogPath "C:\Logs\app.log"
```

**Parameters:**
- `SettingsPath` (optional): Path to settings.json file (defaults to "settings.json")
- `LogPath` (required): Path to log file for operations

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

## Examples

### Complete Configuration Setup

```powershell
# Import required modules
Import-Module AaTurpin.PSConfig

# Define log path
$logPath = "C:\Logs\config-setup.log"

# Create new configuration file
$config = New-SettingsFile -SettingsPath ".\myapp-config.json" -LogPath $logPath -StagingArea "D:\AppStaging"

# Add multiple drive mappings
Add-DriveMapping -Letter "V" -Path "\\server\eng_apps" -SettingsPath ".\myapp-config.json" -LogPath $logPath
Add-DriveMapping -Letter "W" -Path "\\nas\shared_data" -SettingsPath ".\myapp-config.json" -LogPath $logPath

# Add monitored directories with exclusions
Add-MonitoredDirectory -Path "V:\aeapps\fc_tools" -SettingsPath ".\myapp-config.json" -LogPath $logPath
Add-MonitoredDirectory -Path "V:\aeapps\dynamics" -Exclusions @("temp", "logs") -SettingsPath ".\myapp-config.json" -LogPath $logPath
Add-MonitoredDirectory -Path "W:\projects" -Exclusions @("backup", "archive", ".git") -SettingsPath ".\myapp-config.json" -LogPath $logPath

# Verify final configuration
$finalConfig = Read-SettingsFile -SettingsPath ".\myapp-config.json" -LogPath $logPath
Write-Host "Configuration complete: $($finalConfig.driveMappings.Count) drives, $($finalConfig.monitoredDirectories.Count) directories"
```

### Configuration Maintenance

```powershell
$logPath = "C:\Logs\maintenance.log"
$settingsPath = ".\production-config.json"

# Read current configuration
$config = Read-SettingsFile -SettingsPath $settingsPath -LogPath $logPath

# Update staging area
Set-StagingArea -StagingAreaPath "E:\NewProductionStaging" -SettingsPath $settingsPath -LogPath $logPath

# Modify existing drive mapping
Set-DriveMapping -Letter "V" -Path "\\newserver\eng_apps" -SettingsPath $settingsPath -LogPath $logPath

# Update exclusions for a monitored directory
Set-MonitoredDirectory -Path "V:\aeapps\tools" -Exclusions @("temp", "logs", "cache", "debug") -SettingsPath $settingsPath -LogPath $logPath

# Remove obsolete monitored directory
Remove-MonitoredDirectory -Path "V:\old_tools" -SettingsPath $settingsPath -LogPath $logPath
```

## Validation and Error Handling

The module includes comprehensive validation:

- **Drive Letters**: Must be single alphabetic characters
- **UNC Paths**: Must start with `\\` and be properly formatted
- **Uniqueness**: Drive letters and monitored directory paths must be unique
- **JSON Structure**: Automatic validation and repair of configuration structure
- **File Operations**: Thread-safe file operations with retry logic

All operations are logged using the AaTurpin.PSLogger module for complete audit trails.

## Thread Safety

The module integrates with AaTurpin.PSLogger to provide thread-safe file operations, making it suitable for:

- Multi-threaded applications
- Concurrent PowerShell sessions
- Automated scripts running simultaneously
- Enterprise environments with shared configuration files

## License

MIT License - see [LICENSE](https://github.com/aturpin0504/AaTurpin.PSConfig?tab=MIT-1-ov-file) for details.

## Project Links

- **GitHub Repository**: [https://github.com/aturpin0504/AaTurpin.PSConfig](https://github.com/aturpin0504/AaTurpin.PSConfig)
- **PowerShell Gallery**: [AaTurpin.PSConfig](https://www.powershellgallery.com/packages/AaTurpin.PSConfig)
- **Dependencies**: [AaTurpin.PSLogger](https://www.powershellgallery.com/packages/AaTurpin.PSLogger)

## Support

For issues, feature requests, or contributions, please visit the [GitHub repository](https://github.com/aturpin0504/AaTurpin.PSConfig).