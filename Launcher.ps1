param (
    [string]$game,
    [string]$SteamAccount,
    [switch]$ListGames,
    [switch]$ListGameInfo,
    [switch]$Help,
    [switch]$Scan,
    [switch]$ExportGame,
    [switch]$con  # Nouveau paramètre pour contrôler l'affichage de la console
)

# I found this can happen if running an exe created using PS2EXE module
$ScriptPath = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
# Chemin vers le fichier de configuration JSON
$ConfigPath = Join-Path -Path $ScriptPath -ChildPath "config.json"
# Utiliser le répertoire courant pour le fichier de log
$LogFile = Join-Path -Path $ScriptPath -ChildPath "GameLauncher.log"


# Fonction pour afficher la console et récupérer l'entrée utilisateur
function Show-Console {
    if (-not $con) {
        return
    }

    # AllocConsole pour afficher la console si elle n'est pas déjà visible
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleHelper {
        [DllImport("kernel32.dll")]
        public static extern bool AllocConsole();
    }
"@
    [ConsoleHelper]::AllocConsole() | Out-Null

    # Rediriger la sortie standard vers la nouvelle console
    $Host.UI.RawUI.ForegroundColor = "White"
    $Host.UI.RawUI.BackgroundColor = "Black"
    Clear-Host
}

if ($con) {
    Show-Console
}

# Fonction pour écrire dans le fichier de log
function Write-Log {
    param (
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Add-Content -Path $LogFile -Value $logMessage
    if ($con) {
        [Console]::ForegroundColor = $Color
        [Console]::WriteLine($logMessage)
    }
}

# Fonction pour attendre une action de l'utilisateur
function Wait-Action {
    param (
        [string]$Message = "Appuyez sur une touche pour continuer..."
    )
    if ($con) {
        [Console]::ForegroundColor = "White"
	[Console]::WriteLine($Message)
        [Console]::ReadKey($true) | Out-Null
    }
}

# Fonction pour afficher l'aide
function Show-Help {
    $helpMessage = @"
Usage: .\Launcher.exe [options]

Options:
  -game <string>        Specify the name of the game to launch or get info for.
  -ListGames            List all games in the configuration.
  -ListGameInfo         List information for a specific game.
  -Scan                 Automatically scan shortcut in Games directory and add them to configuration.
  -ExportGame           Export games in configuration to steam. Note call python -m pip install -r requirement.txt before.
  -SteamAccount         The name of the steam accound to use. 
  -Help                 Display this help message.

Examples:
  .\Launcher.exe -ListGames
  .\Launcher.exe -ListGameInfo -game 'GameName'
  .\Launcher.exe -Scan'
  .\Launcher.exe -ExportGame -SteamAccount <Name>'
  .\Launcher.exe -game 'GameName'
"@
    Write-Log $helpMessage
}

function Scan-GameFolders {
    $GamesExePath = Join-Path -Path $ScriptPath -ChildPath "Games"

    Write-Log "Scanning for game executables..." -Color "Cyan"
    
    # Common game installation directories
    $commonPaths = @(
        "$GamesExePath"
    )
    
    $foundGames = @()
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Log "Scanning: $path" -Color "Yellow"
            
            # Look for executable files
            $executables = Get-ChildItem -Path $path -Recurse -Include "*.lnk" -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.Name -notmatch "(uninstall|setup|installer|updater|launcher|unity|unreal)"
                } | Select-Object -First 50  # Limit results per folder
            
            foreach ($exe in $executables) {
                $gameName = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)
                $processName = $gameName
                
                $gameInfo = @{
                    Name = $gameName
                    Path = $exe.FullName
                    ProcessName = $processName
                    Directory = $exe.DirectoryName
                }
                
                $foundGames += $gameInfo
                Write-Log "Found: $gameName Directory ($($gameInfo.Directory))" -Color "Green"
            }
        }
    }
    
    if ($foundGames.Count -eq 0) {
        Write-Log "No game executables found in common directories." -Color "Yellow"
        return
    }
    
    Write-Log "`nFound $($foundGames.Count) potential games:" -Color "Cyan"
    for ($i = 0; $i -lt $foundGames.Count; $i++) {
        Write-Log "$($i + 1). $($foundGames[$i].Name) - $($foundGames[$i].Path)"
    }
    Append-To-Config $foundGames
}

function Append-To-Config
{
    param (
        [array]$FoundGames,
        [string]$ConfigurationPath = $ConfigPath
    )
    
    Write-Log "Append new games to configuration" -Color "Yellow"


    try {
        # 1. Open configuration file and read it
        Write-Log "Reading existing configuration from: $ConfigurationPath" -Color "Yellow"
        
        if (-not (Test-Path $ConfigurationPath)) {
            Write-Log "Configuration file not found. Creating new configuration." -Color "Yellow"
            $ExistingConfig = @{}
        } else {
            $configContent = Get-Content -Path $ConfigurationPath -Raw
            if ([string]::IsNullOrWhiteSpace($configContent) -or $configContent.Trim() -eq "{}") {
                Write-Log "Configuration file is empty. Starting with empty configuration." -Color "Yellow"
                $ExistingConfig = @{}
            } else {
                $ExistingConfig = $configContent | ConvertFrom-Json
                Write-Log "Existing configuration loaded successfully." -Color "Green"
                Write-Log "Found $($ExistingConfig.PSObject.Properties.Name.Count) existing game(s) in configuration." -Color "Green"
            }
        }
        
        # 2. Remove elements already present in configuration
        Write-Log "Filtering out games already present in configuration..." -Color "Yellow"
        
        $ExistingGameNames = @()
        if ($ExistingConfig.PSObject.Properties) {
            $ExistingGameNames = $ExistingConfig.PSObject.Properties.Name
            Write-Log "Existing games in configuration: $($ExistingGameNames -join ', ')" -Color "Cyan"
        }
        
        $NewGames = @()
        $SkippedGames = @()
        
        foreach ($game in $FoundGames) {
            if ($ExistingGameNames -contains $game.Name) {
                $SkippedGames += $game.Name
                Write-Log "Skipping '$($game.Name)' - already exists in configuration." -Color "Yellow"
            } else {
                $NewGames += $game
                Write-Log "Adding '$($game.Name)' to new games list." -Color "Green"
            }
        }
        Write-Log "Games to skip (already configured): $($SkippedGames.Count)" -Color "Yellow"
        Write-Log "New games to add: $($NewGames.Count)" -Color "Green"
        
        if ($NewGames.Count -eq 0) {
            Write-Log "No new games to add to configuration. All found games are already configured." -Color "Yellow"
            return
        }
        
        # 3. Append missing entries to the configuration
        Write-Log "Appending new games to configuration..." -Color "Cyan"
        
        # Convert existing config to hashtable if it's a PSCustomObject
        $ConfigHashtable = @{}
        if ($ExistingConfig.PSObject.Properties) {
            foreach ($property in $ExistingConfig.PSObject.Properties) {
                $ConfigHashtable[$property.Name] = $property.Value
            }
        }
        
        $AddedCount = 0
        foreach ($game in $NewGames) {
            try {
                # Create game configuration object
                $gameConfig = @{
                    gameexecutable = $game.Path
                    gameprocessname = $game.ProcessName
                    dateadded = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
                
                # Add to configuration hashtable
                $ConfigHashtable[$game.Name] = $gameConfig
                $AddedCount++
                
                Write-Log "Added '$($game.Name)' to configuration:" -Color "Green"
                Write-Log "  - Executable: $($game.Path)" -Color "White"
                Write-Log "  - Process Name: $($game.ProcessName)" -Color "White"
                Write-Log "  - Directory: $($game.Directory)" -Color "White"
                
            } catch {
                Write-Log "Error adding game '$($game.Name)' to configuration: $($_.Exception.Message)" -Color "Red"
            }
        }
        
        # Save updated configuration to file
        Write-Log "Saving updated configuration to file..." -Color "Yellow"
        
        try {
            $UpdatedConfig = $ConfigHashtable | ConvertTo-Json -Depth 100
            Set-Content -Path $ConfigurationPath -Value $UpdatedConfig -Encoding UTF8
            
            Write-Log "Configuration updated successfully!" -Color "Green"
            Write-Log "Total games in configuration: $($ConfigHashtable.Keys.Count)" -Color "Green"
            Write-Log "New games added: $AddedCount" -Color "Green"
            Write-Log "Configuration saved to: $ConfigurationPath" -Color "Green"
            
        } catch {
            Write-Log "Error saving configuration file: $($_.Exception.Message)" -Color "Red"
            throw
        }
        
    } catch {
        Write-Log "Error in Append-To-Config function: $($_.Exception.Message)" -Color "Red"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Color "Red"
        throw
    }
    
    Write-Log "Configuration update process completed." -Color "Cyan"
}

function Export-Game-Steam{
    $PythonExportPath = Join-Path -Path $ScriptPath -ChildPath "ExportShortcut.py"

    # Run the Python script and capture the output
    $output = python $PythonExportPath --config $ConfigPath --account $SteamAccount --launcher $ScriptPath 2>&1

    # Write the output to the log
    $output | ForEach-Object {
        Write-Log -Message $_ -Color Green
    }
    Wait-Action
}

# Afficher l'aide si l'option -Help est activée
if ($Help) {
    Show-Help
    Wait-Action
    Exit 0
}


Write-Log "Script path: $ScriptPath" -Color Green
Write-Log "Log file path: $LogFile" -Color Green
Write-Log "Configuration file path: $ConfigPath" -Color Green

if ($Scan) {
    Scan-GameFolders 
    Wait-Action
    Exit 0
}
if ($ExportGame)
{
    Export-Game-Steam
    Exit 0
}

# Vérifier si le fichier de configuration existe, sinon le créer
if (-not (Test-Path $ConfigPath)) {
    Write-Log "Configuration file not found. Creating a new one at $ConfigPath" -Color Yellow
    $null = New-Item -Path $ConfigPath -ItemType File
    $Config = @{} | ConvertTo-Json -Depth 100 | Set-Content -Path $ConfigPath
}

# Lire le fichier de configuration JSON
try {
    $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    Write-Log "Configuration loaded successfully:" -Color Green
    $Config | ConvertTo-Json -Depth 100 | Write-Log
} catch {
    Write-Log "Error: Failed to read or parse the configuration file." -Color Red
    Wait-Action
    Exit 1
}



# Ajouter un log pour le nombre de jeux dans la configuration
Write-Log "Number of games in configuration: $($Config.PSObject.Properties.Name.Count)"

# Option pour lister tous les jeux
if ($ListGames) {
    if ($Config.PSObject.Properties.Name.Count -eq 0) {
        Write-Log "No games found in the configuration." -Color Yellow
    } else {
        Write-Log "Games in configuration:" -Color Green
        $Config.PSObject.Properties.Name | ForEach-Object { Write-Log $_ }
    }
    Wait-Action
    Exit 0
}

# Vérifier que le paramètre game est fourni si aucune option n'est activée
if ((-not $ListGames -and -not $ListGameInfo -and -not $game) -or ($ListGameInfo -and -not $game)) {
    Write-Log "Error: game parameter is required." -Color Red
    Show-Help
    Exit 1
}

# Option pour lister les informations d'un jeu spécifique
if ($ListGameInfo -and $game) {
    if (-not $Config.PSObject.Properties[$game]) {
        Write-Log "Error: Game configuration not found for ${game}" -Color Red
        Wait-Action
        Exit 1
    }
    $GameConfig = $Config.PSObject.Properties[$game].Value
    Write-Log "Game information for ${game}:" -Color Green
    $GameConfig | Format-List | Out-String | Write-Log
    Wait-Action
    Exit 0
}

# Vérifier si le jeu existe dans la configuration
if (-not $Config.PSObject.Properties[$game]) {
    Write-Log "Error: Game configuration not found for ${game}" -ForegroundColor Red
    Wait-Action
    Exit 1
}

# Extraire les informations du jeu
$GameConfig = $Config.PSObject.Properties[$game].Value
$GameExecutable = $GameConfig.gameexecutable
$GameProcessName = $GameConfig.gameprocessname

# Vérifier que les informations nécessaires sont présentes dans la configuration
$missingFields = @()
if (-not $GameExecutable) { $missingFields += "gameexecutable" }
if (-not $GameProcessName) { $missingFields += "gameprocessname" }

if ($missingFields.Count -gt 0) {
    Write-Log "Error: Game configuration is incomplete for ${game}. Missing fields: $($missingFields -join ', ')" "Red"
    Exit 1
}

# Ajouter un log pour indiquer quel jeu est lancé
Write-Log "Launching game: ${game}"

# Afficher les messages initiaux
Write-Log "Non-Steam Launcher created by tecnelm."
Write-Log "Do NOT close this window, otherwise it will quit your game."
Write-Log ""

# Vérifier si le fichier exécutable existe
if (-Not (Test-Path $GameExecutable)) {
    Write-Log "Error: Game executable not found at $GameExecutable" "Red"
    Exit 1
}

# Vérifier si le processus du jeu est déjà en cours d'exécution
if (Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue) {
    Write-Log "Game process is already running." "Yellow"
    Exit 0
}

# Lancer le jeu
try {
    Start-Process -FilePath $GameExecutable
    Write-Log "Game launched successfully." "Green"
} catch {
    Write-Log "Error: Failed to launch the game." "Red"
    Exit 1
}

# Attendre le délai initial
Start-Sleep -Seconds 10

# Fonction pour vérifier si le processus du jeu est en cours d'exécution
function Check-GameProcess {
    $processRunning = Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue
    return $processRunning -ne $null
}

# Boucle de détection initiale
$gameProcessDetected = $false
for ($i = 1; $i -le 6; $i++) {
    if (Check-GameProcess) {
        $gameProcessDetected = $true
        Write-Log "Game process detected after $i attempts." "Green"
        break
    }
    if ($i -eq 6) {
        Write-Log "Game process not detected after 6 attempts." "Red"
    } elseif ($i -eq 1) {
        Write-Log "Game process not detected. Retrying in 10 seconds..." "Yellow"
    }
    Start-Sleep -Seconds 10
}

# Vérifier si le processus a été détecté après les tentatives
if (-not $gameProcessDetected) {
    Exit 1
}

# Boucle pour surveiller le processus du jeu
$previousState = $true
try {
    while ($true) {
        $currentState = Check-GameProcess
        if (-not $currentState -and $previousState) {
            Write-Log "Game process is no longer running. Exiting..." "Yellow"
            break
        }
        $previousState = $currentState
        Start-Sleep -Seconds 5
    }
} finally {
    # Fermer les processus du jeu et du launcher
    try {
        if (Check-GameProcess) {
            Stop-Process -Name $GameProcessName -Force
            Write-Log "Game process stopped." "Green"
        }
    } catch {
        Write-Log "Error: Failed to stop processes." "Red"
    }
}

# Quitter le script
Exit