# AaTurpin.PSConfig

A PowerShell module for reading and parsing JSON configuration files with enhanced validation, error handling, and automatic compilation of regex exclusion patterns for optimized file filtering operations.

## Features

- **Robust JSON Parsing**: Read and validate JSON configuration files with comprehensive error handling
- **Enhanced Validation**: Automatic validation of required properties with sensible defaults
- **Regex Pattern Compilation**: Pre-compiles exclusion patterns for optimal performance in file filtering operations
- **Comprehensive Logging**: Seamless integration with `AaTurpin.PSLogger` for detailed operation logging
- **Error Recovery**: Graceful handling of malformed configuration entries with detailed logging
- **Thread-Safe**: Designed to work safely in multi-threaded environments

## Installation

### From NuGet.org (Recommended)
```powershell
# Register NuGet as a package source if not already done
Register-PackageSource -Name NuGet -Location https://www.nuget.org/api/v2 -ProviderName NuGet

# Install the module
Install-Package -Name AaTurpin.PSConfig -Source NuGet -Scope CurrentUser

# Import the module
Import-Module AaTurpin.PSConfig
```

### Alternative NuGet Installation
```powershell
# Using PackageManagement
Find-Package -Name AaTurpin.PSConfig -Source NuGet | Install-Package -Scope CurrentUser
```

### Manual Installation
1. Download the `.nupkg` file from [NuGet.org](https://www.nuget.org/packages/AaTurpin.PSConfig/)
2. Extract the package contents
3. Copy the module files to your PowerShell modules directory:
   - Windows: `$env:USERPROFILE\Documents\PowerShell\Modules\AaTurpin.PSConfig\`
   - Linux/macOS: `~/.local/share/powershell/Modules/AaTurpin.PSConfig/`
4. Import the module:
```powershell
Import-Module AaTurpin.PSConfig
```

## Dependencies

- **AaTurpin.PSLogger** (v1.0.0+) - Required for logging functionality
- **PowerShell 5.1+** - Minimum PowerShell version

## Usage

### Basic Example

```powershell
# Import the required modules
Import-Module AaTurpin.PSLogger
Import-Module AaTurpin.PSConfig

# Read a settings file
$settings = Read-SettingsFile -SettingsPath "C:\Config\settings.json" -LogPath "C:\Logs\app.log"

# Access the parsed settings
Write-Host "Staging Area: $($settings.stagingArea)"
Write-Host "V-Drive Path: $($settings.vDrivePath)"
Write-Host "Monitored Directories: $($settings.monitoredDirectories.Count)"
```

### Advanced Usage with Compiled Exclusion Patterns

```powershell
# Read settings with automatic pattern compilation
$settings = Read-SettingsFile -SettingsPath "settings.json" -LogPath "app.log"

# Use the compiled patterns for efficient file filtering
foreach ($directory in $settings.monitoredDirectories) {
    Write-Host "Directory: $($directory.path)"
    Write-Host "Exclusions: $($directory.exclusions -join ', ')"
    
    # Access pre-compiled regex patterns for performance
    if ($directory.compiledExclusionPatterns) {
        Write-Host "Compiled patterns available: $($directory.compiledExclusionPatterns.Count)"
    }
}
```

## Configuration File Format

The module expects JSON configuration files with the following structure:

```json
{
  "stagingArea": "C:\\StagingArea",
  "vDrivePath": "\\\\server\\share\\path",
  "monitoredDirectories": [
    {
      "path": "V:\\apps\\toolset1",
      "exclusions": ["temp", "logs", "cache"]
    },
    {
      "path": "V:\\apps\\toolset2",
      "exclusions": ["debug", "test"]
    }
  ]
}
```

### Configuration Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `stagingArea` | String | No* | Local staging directory path (defaults to "C:\StagingArea") |
| `vDrivePath` | String | Yes | Network share UNC path |
| `monitoredDirectories` | Array | No | Array of directory objects to monitor |
| `monitoredDirectories[].path` | String | Yes | Directory path to monitor |
| `monitoredDirectories[].exclusions` | Array | No | Subdirectories to exclude from processing |

*If `stagingArea` is missing, the module will automatically set it to "C:\StagingArea" and log a warning.

## Functions

### Read-SettingsFile

Reads and parses a JSON configuration file with enhanced validation and automatic regex pattern compilation.

#### Syntax
```powershell
Read-SettingsFile [-SettingsPath <String>] -LogPath <String>
```

#### Parameters

- **SettingsPath** (Optional): Path to the JSON settings file. Defaults to "settings.json" in the current directory.
- **LogPath** (Required): Path to the log file for operation logging.

#### Returns
`PSCustomObject` containing the parsed settings with compiled exclusion patterns.

#### Example
```powershell
$config = Read-SettingsFile -SettingsPath "C:\Config\app-settings.json" -LogPath "C:\Logs\config.log"
```

## Error Handling

The module provides comprehensive error handling:

- **File Not Found**: Clear error message when settings file doesn't exist
- **Empty Files**: Detection and reporting of empty configuration files
- **Invalid JSON**: Detailed parsing error messages for malformed JSON
- **Missing Properties**: Automatic default value assignment with warnings
- **Malformed Entries**: Graceful skipping of invalid directory entries with logging

## Performance Optimizations

- **Pre-compiled Regex**: Exclusion patterns are compiled once during settings load for optimal performance
- **Efficient Validation**: Streamlined property validation with minimal overhead
- **Memory Efficient**: Careful object creation and cleanup
- **Batch Processing**: Optimized handling of large directory arrays

## Logging Integration

All operations are logged using the `AaTurpin.PSLogger` module with appropriate log levels:

- **Info**: Successful operations and status updates
- **Warning**: Non-critical issues like missing optional properties
- **Error**: Critical errors that prevent operation completion
- **Debug**: Detailed operation information for troubleshooting

## Compatibility

- **Windows PowerShell 5.1+**
- **PowerShell Core 6.0+**
- **Windows, Linux, macOS** (PowerShell Core)

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

### v1.0.0 (2025-07-01)
- Initial release
- JSON configuration file parsing
- Enhanced validation and error handling
- Automatic regex pattern compilation
- Integration with AaTurpin.PSLogger
- Comprehensive documentation and examples

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/aturpin0504/AaTurpin.PSConfig/issues) page
2. Create a new issue with detailed information
3. Include relevant log files and configuration examples

## Related Modules

- **[AaTurpin.PSLogger](https://github.com/aturpin0504/AaTurpin.PSLogger)** - Thread-safe logging capabilities