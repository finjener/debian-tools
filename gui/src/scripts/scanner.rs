use std::fs;
use std::path::{Path, PathBuf};

/// Metadata extracted from script headers
#[derive(Debug, Clone)]
pub struct ScriptMetadata {
    pub id: String,
    pub name: String,
    pub category: String,
    pub script_type: String,
    pub description: String,
    pub filepath: PathBuf,
    
    // Detection metadata
    pub detect_command: Option<String>,
    pub detect_package: Option<String>,
    pub detect_path: Option<String>,
    pub detect_flatpak: Option<String>,
    pub requires_sudo: bool,
}

impl ScriptMetadata {
    /// Parse metadata from script file
    pub fn from_file(path: &Path) -> Result<Self, std::io::Error> {
        let content = fs::read_to_string(path)?;
        
        // Extract metadata from first 30 lines
        let header: String = content
            .lines()
            .take(30)
            .collect::<Vec<_>>()
            .join("\n");
        
        let category = extract_metadata(&header, "CATEGORY")
            .unwrap_or_else(|| "Other".to_string());
        
        let name = extract_metadata(&header, "NAME").unwrap_or_else(|| {
            // Default to capitalized filename
            path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Unknown")
                .replace('_', " ")
                .split_whitespace()
                .map(|w| {
                    let mut c = w.chars();
                    match c.next() {
                        None => String::new(),
                        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" ")
        });
        
        let script_type = extract_metadata(&header, "TYPE")
            .unwrap_or_else(|| "Configure".to_string());
        
        let description = extract_metadata(&header, "DESCRIPTION").unwrap_or_default();
        
        let requires_sudo = extract_metadata(&header, "REQUIRES_SUDO")
            .map(|s| s.to_lowercase() == "true")
            .unwrap_or(false);
        
        // Extract detection metadata
        let detect_command = extract_metadata(&header, "DETECT_COMMAND");
        let detect_package = extract_metadata(&header, "DETECT_PACKAGE");
        let detect_path = extract_metadata(&header, "DETECT_PATH");
        let detect_flatpak = extract_metadata(&header, "DETECT_FLATPAK");
        
        let id = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        Ok(Self {
            id,
            name,
            category,
            script_type,
            description,
            filepath: path.to_path_buf(),
            requires_sudo,
            detect_command,
            detect_package,
            detect_path,
            detect_flatpak,
        })
    }
}

/// Extract metadata value from script header
fn extract_metadata(header: &str, key: &str) -> Option<String> {
    // Match: # DEBIAN_TOOLS_KEY: value
    let pattern = format!("# DEBIAN_TOOLS_{key}:");
    
    for line in header.lines() {
        if let Some(pos) = line.find(&pattern) {
            let value_start = pos + pattern.len();
            if value_start < line.len() {
                return Some(line[value_start..].trim().to_string());
            }
        }
    }
    
    None
}

/// Scan scripts directory and discover all scripts
pub fn scan_scripts_directory(scripts_dir: &Path) -> Vec<ScriptMetadata> {
    let mut scripts = Vec::new();
    
    fn scan_recursive(dir: &Path, scripts: &mut Vec<ScriptMetadata>) {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                
                if path.is_dir() {
                    // Recurse into subdirectories
                    scan_recursive(&path, scripts);
                } else if path.extension().and_then(|s| s.to_str()) == Some("sh") {
                    // Skip common.sh and other utility scripts
                    if let Some(filename) = path.file_name().and_then(|s| s.to_str()) {
                        if filename == "common.sh" || filename == "apt_helper.sh" {
                            continue;
                        }
                    }
                    
                    // Parse .sh files
                    if let Ok(metadata) = ScriptMetadata::from_file(&path) {
                        scripts.push(metadata);
                    }
                }
            }
        }
    }
    
    scan_recursive(scripts_dir, &mut scripts);
    
    // Sort alphabetically by name
    scripts.sort_by(|a, b| a.name.cmp(&b.name));
    
    scripts
}
