//! Configuration system for debian-tools GUI

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::fs;

/// Main application configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Custom scripts directory (overrides default)
    pub scripts_dir: Option<PathBuf>,
    /// Custom log directory
    pub log_dir: Option<PathBuf>,
    /// Custom backup directory
    pub backup_dir: Option<PathBuf>,
    /// Default timeout for scripts in minutes
    pub default_timeout_minutes: u64,
    /// Enable pre-execution network check
    pub check_network: bool,
    /// Enable pre-execution disk space check
    pub check_disk_space: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            scripts_dir: None,
            log_dir: None,
            backup_dir: None,
            default_timeout_minutes: 30,
            check_network: true,
            check_disk_space: true,
        }
    }
}

/// User preferences that persist between sessions
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Preferences {
    /// Theme preference (not yet implemented in Iced 0.13)
    pub theme: ThemePreference,
    /// Last selected category ID
    pub last_category: Option<String>,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            theme: ThemePreference::System,
            last_category: None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default)]
pub enum ThemePreference {
    #[default]
    System,
    Light,
    Dark,
}

impl Config {
    /// Load configuration from file or return defaults
    pub fn load() -> Self {
        // Check environment variable first
        if let Ok(path) = std::env::var("DEBIAN_TOOLS_CONFIG") {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(config) = toml::from_str(&content) {
                    return config;
                }
            }
        }

        // Check standard config location
        if let Some(config_dir) = dirs::config_dir() {
            let config_path = config_dir.join("debian-tools").join("config.toml");
            if let Ok(content) = fs::read_to_string(&config_path) {
                if let Ok(config) = toml::from_str(&content) {
                    return config;
                }
            }
        }

        // Return defaults
        Self::default()
    }

    /// Get scripts directory, checking environment overrides
    pub fn get_scripts_dir(&self) -> Option<PathBuf> {
        // Environment variable takes precedence
        if let Ok(dir) = std::env::var("DEBIAN_TOOLS_SCRIPTS_DIR") {
            return Some(PathBuf::from(dir));
        }
        self.scripts_dir.clone()
    }

    /// Get backup directory, checking environment overrides
    pub fn get_backup_dir(&self) -> PathBuf {
        // Environment variable takes precedence
        if let Ok(dir) = std::env::var("DEBIAN_TOOLS_BACKUP_DIR") {
            return PathBuf::from(dir);
        }
        if let Ok(dir) = std::env::var("DT_BACKUP_DIR") {
            return PathBuf::from(dir);
        }

        self.backup_dir.clone().unwrap_or_else(|| {
            dirs::data_local_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("debian-tools")
                .join("backups")
        })
    }

    /// Get data directory, checking environment overrides
    pub fn get_data_dir(&self) -> PathBuf {
        if let Ok(dir) = std::env::var("DEBIAN_TOOLS_DATA_DIR") {
            return PathBuf::from(dir);
        }
        if let Ok(dir) = std::env::var("DT_DATA_DIR") {
            return PathBuf::from(dir);
        }

        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("debian-tools")
    }

    /// Get log directory, checking environment overrides
    pub fn get_log_dir(&self) -> PathBuf {
        // Environment variable takes precedence
        if let Ok(dir) = std::env::var("DEBIAN_TOOLS_LOG_DIR") {
            return PathBuf::from(dir);
        }
        if let Ok(dir) = std::env::var("DT_LOG_DIR") {
            return PathBuf::from(dir);
        }
        
        self.log_dir.clone().unwrap_or_else(|| {
            dirs::data_local_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("debian-tools")
                .join("logs")
        })
    }
}

impl Preferences {
    /// Get preferences file path
    fn path() -> Option<PathBuf> {
        dirs::config_dir().map(|d| d.join("debian-tools").join("preferences.json"))
    }

    /// Load preferences from file or return defaults
    pub fn load() -> Self {
        if let Some(path) = Self::path() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(prefs) = serde_json::from_str(&content) {
                    return prefs;
                }
            }
        }
        Self::default()
    }

    /// Save preferences to file
    pub fn save(&self) -> Result<(), std::io::Error> {
        if let Some(path) = Self::path() {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            let content = serde_json::to_string_pretty(self)?;
            fs::write(path, content)?;
        }
        Ok(())
    }
}
