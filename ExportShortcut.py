import argparse
import os 
from steam_vdf import users
import vdf
import logging
import json
from typing import Dict, List, Optional, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cli")

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description=" Export Vdf shortcut")

    parser.add_argument("--config", 
                            type=str,    
                            help="Path to config file",
                           )
    parser.add_argument("--account", 
                            type=str, 
                            help="Steam account name")
    parser.add_argument("--launcher",
                            type=str,
                            help="Path to launcher executable")
        
    # Check if command was provided, if not show help
    return parser.parse_args()

def create_shortcut_entry(app_name: str, launcher_path: str,steam_app_name:str) -> Dict[str, Any]:
    """
    Create a new shortcut entry for Steam
    
    Args:
        app_name: Name of the application
        launcher_path: Path to the launcher executable
        
    Returns:
        Dictionary containing the shortcut entry data
    """
    # Validate inputs
    if not app_name or not launcher_path or not steam_app_name:
        raise ValueError("app_name, launcher_path and steam_app_name cannot be empty")
    
    if not os.path.exists(launcher_path):
        raise FileNotFoundError(f"Launcher path does not exist: {launcher_path}")
    
    # Get the start directory (default to executable's directory)
    exe_dir = os.path.dirname(launcher_path)

    # Get launch options (optional)
    launch_options = f'-Game "{app_name}"'

    # Create the shortcut entry
    entry = {
        "appname": steam_app_name,
        "exe": f'"{launcher_path}"',
        "StartDir": exe_dir,
        "icon": "",
        "ShortcutPath": "",
        "LaunchOptions": launch_options,
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "LastPlayTime": 0,
        "tags": "Launcher",
    }

    return entry


def load_shortcuts_file(shortcuts_vdf: str) -> Dict[str, Any]:
    """
    Load shortcuts.vdf file using binary mode
    
    Args:
        shortcuts_vdf: Path to the shortcuts.vdf file
        
    Returns:
        Dictionary containing shortcuts data
    """
    try:
        if os.path.exists(shortcuts_vdf):
            with open(shortcuts_vdf, "rb") as f:  # Use binary mode
                shortcuts = vdf.binary_load(f) 
                return shortcuts
        else:
            logger.debug("No shortcuts.vdf found at: %s", shortcuts_vdf)
            return {"shortcuts": {}}
    except Exception as e:
        logger.error("Error loading shortcuts.vdf: %s", e)
        return {"shortcuts": {}}


def shortcut_already_exists(shortcuts: Dict[str, Any], app_name: str) -> bool:
    """
    Check if a shortcut already exists for the given app name
    
    Args:
        shortcuts: Dictionary containing shortcuts data
        app_name: Name of the application to check
        
    Returns:
        True if shortcut exists, False otherwise
    """
    if "shortcuts" not in shortcuts:
        return False
        
    for shortcut_id in shortcuts["shortcuts"]:
        shortcut = shortcuts["shortcuts"][shortcut_id]
        # Check both possible key names for app name
        shortcut_name = shortcut.get("appname") or shortcut.get("AppName")
        if shortcut_name and shortcut_name.lower() == app_name.lower():
            return True

    return False


def add_shortcut(vdf_path: str, app_name: str, launcher_path: str,steam_app_name:str = None) -> bool:
    """
    Add a shortcut to the Steam shortcuts file
    
    Args:
        vdf_path: Path to the shortcuts.vdf file
        app_name: Name of the application
        launcher_path: Path to the launcher executable
        
    Returns:
        True if successful, False otherwise
    """
    try:
        if not os.path.exists(vdf_path):
            logger.error("VDF file does not exist: %s", vdf_path)
            return False
            
        shortcuts = load_shortcuts_file(vdf_path)
        
        if shortcut_already_exists(shortcuts, app_name):
            logger.info("Shortcut for '%s' already exists, skipping", app_name)
            return True
        steam_app_name = app_name if steam_app_name is None else steam_app_name
        game_entry = create_shortcut_entry(app_name, launcher_path,steam_app_name)
        shortcuts = users.add_shortcut_to_shortcuts(shortcuts, game_entry)
        
        if users.save_shortcuts(vdf_path, shortcuts):
            logger.info("Shortcut for '%s' added successfully", app_name)
            return True
        else:
            logger.error("Failed to save shortcuts for '%s'", app_name)
            return False
            
    except Exception as e:
        logger.error("Error adding shortcut for '%s': %s", app_name, e)
        return False
        

def get_steam_user_names(steam_path: str) -> Dict[str, Dict[str, str]]:
    """
    Get Steam account names from both loginusers.vdf and config.vdf
    
    Args:
        steam_path: Path to Steam installation directory
        
    Returns:
        Dictionary mapping user IDs to account information
    """
    logger.debug("Attempting to read Steam user names")
    user_names = {}

    # Process loginusers.vdf
    login_file = os.path.join(steam_path, "config", "loginusers.vdf")
    try:
        if os.path.exists(login_file):
            with open(login_file, "r", encoding="utf-8") as f:
                login_data = vdf.load(f)
                users._process_loginusers_data(login_data, user_names)
        else:
            logger.warning("loginusers.vdf not found at: %s", login_file)
    except Exception as e:
        logger.error("Error reading loginusers.vdf: %s", e)

    # Process config.vdf
    config_file = os.path.join(steam_path, "config", "config.vdf")
    try:
        if os.path.exists(config_file):
            with open(config_file, "r", encoding="utf-8") as f:
                config_data = vdf.load(f)
                users._process_config_data(config_data, user_names)
        else:
            logger.warning("config.vdf not found at: %s", config_file)
    except Exception as e:
        logger.error("Error reading config.vdf: %s", e)

    return user_names


def get_vdf_path(account_name: str, selected_library: str) -> Optional[str]:
    """
    Get the path to the shortcuts.vdf file for a specific Steam account
    
    Args:
        account_name: Steam account name
        selected_library: Path to Steam library
        
    Returns:
        Path to shortcuts.vdf file or None if not found
    """
    shortcuts_vdf = os.path.join(selected_library, "userdata")

    if not os.path.exists(shortcuts_vdf):
        logger.error("No userdata directory found at %s", shortcuts_vdf)
        return None

    user_dirs = [
        d for d in os.listdir(shortcuts_vdf)
        if os.path.isdir(os.path.join(shortcuts_vdf, d))
    ]

    if not user_dirs:
        logger.error("No Steam users found in userdata directory")
        return None
        
    user_names = get_steam_user_names(selected_library)
    user_dir_id = None
    
    for user_dir in user_dirs:
        user_info = user_names.get(
            user_dir,
            {"PersonaName": "Unknown Account", "AccountName": "Unknown Account"}
        )
        if account_name.lower() == user_info["AccountName"].lower():
            user_dir_id = user_dir
            break
            
    if user_dir_id is None:
        logger.error("Account '%s' not found in Steam userdata", account_name)
        return None
        
    shortcuts_vdf_path = os.path.join(
        shortcuts_vdf, user_dir_id, "config", "shortcuts.vdf"
    )
    
    return shortcuts_vdf_path


def load_config(config_path: str) -> Optional[Dict[str, Any]]:
    """
    Load configuration from JSON file
    
    Args:
        config_path: Path to the configuration file
        
    Returns:
        Configuration data or None if failed to load
    """
    try:
        if not os.path.exists(config_path):
            logger.error("Configuration file not found: %s", config_path)
            return None
            
        with open(config_path, 'r', encoding='utf-8-sig') as file:
            config_data = json.load(file)
            
        if not config_data:
            logger.error("Configuration file is empty")
            return None
            
        return config_data
        
    except json.JSONDecodeError as e:
        logger.error("Invalid JSON in configuration file: %s", e)
        return None
    except Exception as e:
        logger.error("Error loading configuration file: %s", e)
        return None


def main():
    """
    Main function to process shortcuts
    """
    # Configuration
    args = parse_arguments()

    config_path = os.path.abspath(args.config)
    account_name = args.account
    launcher_path = os.path.abspath(args.launcher)
    
    # Load configuration
    config_data = load_config(config_path)
    if config_data is None:
        logger.error("Failed to load configuration, exiting")
        return 1

    # Find Steam library
    try:
        selected_library = users.find_steam_library(None)
        if not selected_library:
            logger.error("Steam library not found")
            return 1
    except Exception as e:
        logger.error("Error finding Steam library: %s", e)
        return 1

    # Get shortcuts VDF path
    shortcuts_vdf = get_vdf_path(account_name, selected_library)
    if shortcuts_vdf is None:
        logger.error("Failed to get shortcuts VDF path")
        return 1
    
    # Process each application in config
    success_count = 0
    total_count = len(config_data)
    
    for app_name in config_data:
        steam_app_name = None
        if "applicationname" in config_data[app_name]:
            steam_app_name = config_data[app_name]["applicationname"]
        if add_shortcut(shortcuts_vdf, app_name, launcher_path,steam_app_name):
            success_count += 1
        else:
            logger.warning("Failed to add shortcut for: %s", app_name)
    
    logger.info("Processing complete: %d/%d shortcuts processed successfully", 
                success_count, total_count)
    
    return 0 if success_count == total_count else 1


if __name__ == "__main__":
    exit(main())