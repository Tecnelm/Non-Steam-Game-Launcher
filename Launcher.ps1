param (
    [string]$game,
    [switch]$ListGames,
    [switch]$ListGameInfo,
    [switch]$Help,
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
  -Help                 Display this help message.

Examples:
  .\Launcher.exe -ListGames
  .\Launcher.exe -ListGameInfo -game 'GameName'
  .\Launcher.exe -game 'GameName'
"@
    Write-Log $helpMessage
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