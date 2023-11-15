//! Script types and metadata definitions

use std::path::PathBuf;

/// Script categories matching the debian-tools directory structure
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Category {
    Security,
    Desktop,
    Packages,
    System,
    Vpn,
    Browsers,
    Editors,
    Development,
    Virtualization,
    Android,
    Communication,
    Gaming,
    Other,
}

impl Category {
    pub fn all() -> &'static [Category] {
        &[
            Category::Security,
            Category::Desktop,
            Category::Packages,
            Category::System,
            Category::Vpn,
            Category::Browsers,
            Category::Editors,
            Category::Development,
            Category::Virtualization,
            Category::Android,
            Category::Communication,
            Category::Gaming,
            Category::Other,
        ]
    }

    pub fn name(&self) -> &'static str {
        match self {
            Category::Security => "Security",
            Category::Desktop => "Desktop",
            Category::Packages => "Packages",
            Category::System => "System",
            Category::Vpn => "VPN",
            Category::Browsers => "Browsers",
            Category::Editors => "AI Editors",
            Category::Development => "Development",
            Category::Virtualization => "Virtualization",
            Category::Android => "Android",
            Category::Communication => "Communication",
            Category::Gaming => "Gaming",
            Category::Other => "Other",
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            Category::Security => "🔒",
            Category::Desktop => "🖥️",
            Category::Packages => "📦",
            Category::System => "⚙️",
            Category::Vpn => "🔐",
            Category::Browsers => "🌐",
            Category::Editors => "✏️",
            Category::Development => "💻",
            Category::Virtualization => "📱",
            Category::Android => "🤖",
            Category::Communication => "💬",
            Category::Gaming => "🎮",
            Category::Other => "📁",
        }
    }
    
    /// Parse category from string (case-insensitive), returns None if unknown
    pub fn try_from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "security" => Some(Category::Security),
            "desktop" => Some(Category::Desktop),
            "packages" => Some(Category::Packages),
            "system" => Some(Category::System),
            "vpn" => Some(Category::Vpn),
            "browsers" => Some(Category::Browsers),
            "editors" | "ai editors" | "ai-editors" | "ai_editors" => Some(Category::Editors),
            "development" => Some(Category::Development),
            "virtualization" => Some(Category::Virtualization),
            "android" => Some(Category::Android),
            "communication" => Some(Category::Communication),
            "gaming" => Some(Category::Gaming),
            _ => None,
        }
    }
    
    /// Parse category from string (case-insensitive), defaults to Other if unknown
    pub fn from_str(s: &str) -> Self {
        Self::try_from_str(s).unwrap_or(Category::Other)
    }
}

/// Operations that scripts can perform
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Operation {
    Backup,
    BackupEncrypted,
    Restore(PathBuf),
    RestoreInteractive,
    List,
    Show,
    Install,
    Uninstall,
    Configure,
    Simulate,
}

impl Operation {
    pub fn label(&self) -> &'static str {
        match self {
            Operation::Backup => "Backup",
            Operation::BackupEncrypted => "🔒 Encrypted",
            Operation::Restore(_) => "Restore...",
            Operation::RestoreInteractive => "Restore",
            Operation::List => "List",
            Operation::Show => "Show",
            Operation::Install => "Install",
            Operation::Uninstall => "Uninstall",
            Operation::Configure => "Configure",
            Operation::Simulate => "Simulate",
        }
    }

    pub fn to_args(&self) -> Vec<String> {
        match self {
            Operation::Backup => vec!["--backup".into()],
            Operation::BackupEncrypted => vec!["--backup-encrypted".into()],
            Operation::Restore(path) => vec!["--restore".into(), path.display().to_string()],
            Operation::RestoreInteractive => vec!["--restore".into()],
            Operation::List => vec!["--list".into()],
            Operation::Show => vec!["--show".into()],
            Operation::Install => vec![],
            Operation::Uninstall => vec!["-u".into()],
            Operation::Configure => vec![],
            Operation::Simulate => vec!["--simulate-only".into()],
        }
    }
}

/// Script type determines available operations
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScriptType {
    BackupRestore,
    InstallUninstall,
    PackageManager,
    Configure,
    Interactive,
}

impl ScriptType {
    /// Parse script type from string
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().replace("-", "").replace("_", "").as_str() {
            "backuprestore" => ScriptType::BackupRestore,
            "installuninstall" => ScriptType::InstallUninstall,
            "packagemanager" => ScriptType::PackageManager,
            "configure" => ScriptType::Configure,
            "interactive" => ScriptType::Interactive,
            _ => ScriptType::Configure,  // Default
        }
    }
}

/// Metadata for a single script
#[derive(Debug, Clone)]
pub struct ScriptMeta {
    pub id: String,
    pub name: String,
    pub category: Category,
    pub script_type: ScriptType,
    pub filename: String,
    pub requires_sudo: bool,
    /// Optional custom timeout in minutes (default: 30)
    pub timeout_minutes: Option<u64>,
    
    // Detection metadata
    pub detect_command: Option<String>,
    pub detect_package: Option<String>,
    pub detect_path: Option<String>,
    pub detect_flatpak: Option<String>,
}

impl ScriptMeta {
    pub fn available_operations(&self) -> Vec<Operation> {
        match self.script_type {
            ScriptType::BackupRestore => vec![
                Operation::Backup,
                Operation::BackupEncrypted,
                Operation::RestoreInteractive,
                Operation::List,
                Operation::Show,
            ],
            ScriptType::InstallUninstall => vec![
                Operation::Install,
                Operation::Uninstall,
            ],
            ScriptType::PackageManager => vec![
                Operation::Install,
                Operation::Simulate,
            ],
            ScriptType::Configure => vec![
                Operation::Configure,
            ],
            ScriptType::Interactive => vec![],
        }
    }
}
