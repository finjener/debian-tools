//! Embedded scripts module - hybrid approach
//! 
//! In debug mode: loads scripts from disk (fast iteration)
//! In release mode: embeds scripts in binary (self-contained distribution)

use rust_embed::RustEmbed;
use std::path::PathBuf;
use std::fs;
use std::io;

/// Embedded scripts directory - loaded at compile time in release mode
#[derive(RustEmbed)]
#[folder = "../scripts/"]
pub struct ScriptsAsset;

/// Extract embedded scripts to a cache directory
/// 
/// Uses XDG cache directory for persistence between runs
pub fn extract_scripts() -> Result<PathBuf, io::Error> {
    // Use XDG cache directory
    let cache_dir = dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from(".cache"))
        .join("debian-tools")
        .join("scripts");
    
    // Check if scripts are already extracted and up-to-date
    let version_file = cache_dir.join(".version");
    let current_version = env!("CARGO_PKG_VERSION");
    
    let needs_extraction = if cache_dir.exists() {
        // Check version to see if we need to re-extract
        match fs::read_to_string(&version_file) {
            Ok(cached_version) => cached_version.trim() != current_version,
            Err(_) => true, // No version file, need to extract
        }
    } else {
        true // Cache doesn't exist
    };
    
    if needs_extraction {
        // Clear old cache if it exists
        if cache_dir.exists() {
            fs::remove_dir_all(&cache_dir)?;
        }
        
        // Create cache directory
        fs::create_dir_all(&cache_dir)?;
        
        // Extract all embedded files
        for file_path in ScriptsAsset::iter() {
            let file_path_str = file_path.as_ref();
            
            if let Some(content) = ScriptsAsset::get(file_path_str) {
                let target_path = cache_dir.join(file_path_str);
                
                // Create parent directories
                if let Some(parent) = target_path.parent() {
                    fs::create_dir_all(parent)?;
                }
                
                // Write file
                fs::write(&target_path, content.data.as_ref())?;
                
                // Make shell scripts executable
                if file_path_str.ends_with(".sh") {
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::PermissionsExt;
                        let mut perms = fs::metadata(&target_path)?.permissions();
                        perms.set_mode(0o755); // rwxr-xr-x
                        fs::set_permissions(&target_path, perms)?;
                    }
                }
            }
        }
        
        // Write version file
        fs::write(version_file, current_version)?;
        
        eprintln!("✓ Extracted embedded scripts to: {}", cache_dir.display());
    } else {
        eprintln!("✓ Using cached scripts from: {}", cache_dir.display());
    }
    
    Ok(cache_dir)
}

/// Check if we should use embedded scripts
/// 
/// Returns true in release builds, false in debug builds (thanks to debug-embed feature)
pub fn should_use_embedded() -> bool {
    // In debug mode with debug-embed feature, this returns false
    // In release mode, this returns true
    !cfg!(debug_assertions)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_should_use_embedded() {
        // In debug builds, should return false
        #[cfg(debug_assertions)]
        assert!(!should_use_embedded());
        
        // In release builds, should return true
        #[cfg(not(debug_assertions))]
        assert!(should_use_embedded());
    }
}
