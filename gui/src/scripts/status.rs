//! Dynamic install status detection for scripts
//! 
//! Scripts declare their own detection logic via metadata headers.
//! No hardcoded registry needed!

use std::path::Path;
use std::process::Command;
use crate::scripts::ScriptMeta;

/// Check if a script is installed using its detection metadata
/// 
/// Returns Some(true) if installed, Some(false) if not installed, None if no detection method specified
pub fn check_installed(script: &ScriptMeta) -> Option<bool> {
    // Try detection methods in priority order
    
    // 1. Command check (most reliable - tests if it actually works)
    if let Some(cmd_str) = &script.detect_command {
        return check_command(cmd_str);
    }
    
    // 2. Package check (checks dpkg database)
    if let Some(pkg) = &script.detect_package {
        return Some(is_dpkg_installed(pkg));
    }
    
    // 3. Path check (simple existence)
    if let Some(path_str) = &script.detect_path {
        return Some(Path::new(path_str).exists());
    }
    
    // 4. Flatpak check
    if let Some(flatpak_id) = &script.detect_flatpak {
        return Some(is_flatpak_installed(flatpak_id));
    }
    
    // No detection method specified - return None (neutral status)
    None
}

/// Check if a command runs successfully
fn check_command(cmd_str: &str) -> Option<bool> {
    let parts: Vec<&str> = cmd_str.split_whitespace().collect();
    if parts.is_empty() {
        return None;
    }
    
    Command::new(parts[0])
        .args(&parts[1..])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .ok()
}

/// Check if a package is installed via dpkg
fn is_dpkg_installed(package: &str) -> bool {
    Command::new("dpkg-query")
        .args(["-W", "-f=${Status}", package])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.contains("install ok installed"))
        .unwrap_or(false)
}

/// Check if a flatpak is installed
fn is_flatpak_installed(app_id: &str) -> bool {
    Command::new("flatpak")
        .args(["info", app_id])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
