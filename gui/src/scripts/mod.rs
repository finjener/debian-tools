//! Script management and registry

mod types;
pub mod runner;
pub mod status;
mod scanner;

pub use types::*;
use scanner::{scan_scripts_directory, ScriptMetadata};
use std::path::Path;
use std::collections::HashMap;

/// Registry of discovered scripts
pub struct ScriptRegistry {
    scripts: Vec<ScriptMeta>,
    by_id: HashMap<String, usize>,
}

impl ScriptRegistry {
    /// Create registry by scanning scripts directory
    pub fn new_from_path(scripts_dir: &Path) -> Self {
        let discovered = scan_scripts_directory(scripts_dir);
        
        let mut scripts = Vec::new();
        let mut by_id = HashMap::new();
        
        for (idx, metadata) in discovered.iter().enumerate() {
            // Convert ScriptMetadata to ScriptMeta
            let script_meta = ScriptMeta {
                id: metadata.id.clone(),
                name: metadata.name.clone(),
                category: Category::from_str(&metadata.category),
                script_type: ScriptType::from_str(&metadata.script_type),
                filename: metadata
                    .filepath
                    .strip_prefix(scripts_dir)
                    .unwrap_or(&metadata.filepath)
                    .to_string_lossy()
                    .to_string(),
                requires_sudo: metadata.requires_sudo,
                timeout_minutes: None,
                
                // Detection metadata
                detect_command: metadata.detect_command.clone(),
                detect_package: metadata.detect_package.clone(),
                detect_path: metadata.detect_path.clone(),
                detect_flatpak: metadata.detect_flatpak.clone(),
            };
            
            by_id.insert(metadata.id.clone(), idx);
            scripts.push(script_meta);
        }
        
        Self { scripts, by_id }
    }
    
    /// Get script by ID
    pub fn get(&self, id: &str) -> Option<&ScriptMeta> {
        self.by_id.get(id).and_then(|&idx| self.scripts.get(idx))
    }
    
    /// Get all scripts in a category (alphabetically sorted)
    pub fn by_category(&self, category: Category) -> Vec<&ScriptMeta> {
        self.scripts
            .iter()
            .filter(|s| s.category == category)
            .collect()
    }
    
    /// Get all scripts
    pub fn all(&self) -> impl Iterator<Item = &ScriptMeta> {
        self.scripts.iter()
    }
}
