# Game Launcher

A PowerShell-based game launcher utility designed to manage and monitor game processes through Steam or other platforms. This tool provides a simple interface to launch games while monitoring their execution status.

## Features

- **Game Management**: Launch games through a configuration-based system
- **Process Monitoring**: Automatically detect and monitor game processes
- **Logging**: Comprehensive logging system for debugging and monitoring
- **Configuration-driven**: JSON-based configuration for easy game management
- **Console Control**: Optional console display for debugging
- **Error Handling**: Robust error handling and validation

## Requirements

- Windows Operating System
- PowerShell 5.1 or later
- PS2EXE module (for building executable)
- python 3.11 with module steam-vdf and pyreadline3

## Installation

### Building the Executable

1. Install the PS2EXE module:
```powershell
Install-Module -Name PS2EXE
```

2. Convert the PowerShell script to executable:
```powershell
ps2exe .\Launcher.ps1 .\Launcher.exe -noConsole
```

### Alternative Build Options

For debugging purposes, you can build with console enabled:
```powershell
ps2exe .\Launcher.ps1 .\Launcher.exe
```

## Configuration

### Setting up config.json

Create or modify the `config.json` file in the same directory as the executable:

```json
{
    "YourGameKey": {
        "gameexecutable": "PathToLaunchGame",
        "gameprocessname": "NameOfTheProcessToSearch"
    },
    "Steam Game Example": {
        "applicationname" : "Your Application override"
        "gameexecutable": "C:\\Program Files (x86)\\Steam\\steam.exe",
        "gameprocessname": "GameProcess"
    },
    "Direct Game Example": {
        "gameexecutable": "C:\\Games\\MyGame\\game.exe",
        "gameprocessname": "game"
    }
}
```
`applicationname` Will be use in export shortcut to steam functionnality to override default name (json key)
#### Configuration Parameters

- **gameexecutable**: Full path to the game executable or launcher
- **gameprocessname**: Name of the process to monitor (without .exe extension)

## Usage

### Command Line Options

```
.\Launcher.exe [options]

Options:
  -game <string>        Specify the name of the game to launch or get info for
  -ListGames            List all games in the configuration
  -ListGameInfo         List information for a specific game
  -Help                 Display help message
  -con                  Enable console display for debugging
```

### Examples

#### Launch a Game
```powershell
.\Launcher.exe -game "YourGameKey"
```

#### List All Available Games
```powershell
.\Launcher.exe -ListGames
```

#### Get Game Information
```powershell
.\Launcher.exe -ListGameInfo -game "YourGameKey"
```
#### Export game to steam 
```powershell
>First time : python -m pip install -r requirement.txt
.\Launcher.exe -ExportGame -con -SteamAccount <SteamAccountName>
```
#### Auto Scan functionnality
Will create entry in configuration for *.lnk files in `<scriptDir>\Games`
```powershell
.\Launcher.exe -scan -con
```

#### Debug Mode (with console)
```powershell
.\Launcher.exe -game "YourGameKey" -con
```

#### Display Help
```powershell
.\Launcher.exe -Help
```

## How It Works

1. **Initialization**: The launcher reads the configuration file and validates the game settings
2. **Game Launch**: Starts the specified game executable
3. **Process Detection**: Waits up to 60 seconds (6 attempts × 10 seconds) to detect the game process
4. **Monitoring**: Continuously monitors the game process every 5 seconds
5. **Cleanup**: Automatically exits when the game process terminates

## Logging

The launcher creates a log file (`GameLauncher.log`) in the same directory with detailed information about:
- Script execution steps
- Configuration loading
- Game launch status
- Process monitoring events
- Error messages with timestamps

## File Structure

```
ProjectDirectory/
├── Launcher.ps1          # Main PowerShell script
├── Launcher.exe          # Compiled executable (after build)
├── config.json           # Game configuration file
├── GameLauncher.log      # Runtime log file (auto-generated)
└── README.md            # This file
```

## Troubleshooting

### Common Issues

**Game not launching:**
- Verify the `gameexecutable` path is correct and file exists
- Check that you have permissions to execute the game
- Review the log file for specific error messages

**Process not detected:**
- Ensure `gameprocessname` matches the actual process name (check Task Manager)
- Some games may take longer than 60 seconds to start - adjust timing if needed
- Process name should not include the .exe extension

**Configuration errors:**
- Validate JSON syntax in config.json
- Ensure all required fields are present for each game entry
- Check file paths use double backslashes (\\) or forward slashes (/)

### Debug Mode

Use the `-con` parameter to enable console output for real-time debugging:
```powershell
.\Launcher.exe -game "YourGameKey" -con
```
## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this launcher.

## License

This project is provided as-is for educational and personal use.

## Credits

Created by tecnelm - Non-Steam Launcher utility for game management and monitoring. 
