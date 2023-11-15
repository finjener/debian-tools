//! Async script execution with cancellation, timeout, and pre-execution validation

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;
use tokio::fs::File;
use tokio::io::{AsyncBufReadExt, BufReader, AsyncSeekExt};
use tokio::process::Command;
use tokio::sync::mpsc;

use super::{Operation, ScriptMeta};

/// Output from a running script
#[derive(Debug, Clone)]
pub enum ScriptOutput {
    Line(String),
    Finished { success: bool, code: Option<i32> },
    Error(String),
    Cancelled,
    Timeout,
}

/// Pre-execution check results
#[derive(Debug)]
pub enum PreCheckResult {
    Ok,
    NetworkUnavailable,
    ScriptNotFound(PathBuf),
    DiskSpaceLow(u64), // bytes available
}



/// Runner configuration (derived from GUI config/environment)
#[derive(Debug, Clone)]
pub struct RunnerConfig {
    pub scripts_dir: PathBuf,
    pub log_dir: PathBuf,
    pub backup_dir: PathBuf,
    pub data_dir: PathBuf,
    pub default_timeout_minutes: u64,
    pub check_network: bool,
    pub check_disk_space: bool,
}


/// Runs a script asynchronously and streams output
pub struct ScriptRunner {
    cfg: RunnerConfig,
}

impl ScriptRunner {
    pub fn new(cfg: RunnerConfig) -> Self {
        Self { cfg }
    }

    /// Check prerequisites before running a script
    pub fn pre_check(&self, script: &ScriptMeta) -> PreCheckResult {
        let script_path = self.cfg.scripts_dir.join(&&script.filename);
        
        // Check script file exists
        if !script_path.exists() {
            return PreCheckResult::ScriptNotFound(script_path);
        }

        // Scripts that typically need network (heuristic based on type)
        let needs_network = matches!(
            script.script_type,
            super::ScriptType::InstallUninstall | super::ScriptType::PackageManager
        );

        if self.cfg.check_network && needs_network && !Self::check_network() {
            return PreCheckResult::NetworkUnavailable;
        }

        // Optional: Check disk space (warn if < 500MB)
        if self.cfg.check_disk_space {
            if let Some(available) = Self::check_disk_space() {
                if available < 500 * 1024 * 1024 {
                    return PreCheckResult::DiskSpaceLow(available);
                }
            }
        }

        PreCheckResult::Ok
    }

    /// Check network connectivity
    fn check_network() -> bool {
        // Quick DNS check - try to resolve a known domain
        std::process::Command::new("ping")
            .args(["-c", "1", "-W", "2", "1.1.1.1"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Check available disk space on root partition
    fn check_disk_space() -> Option<u64> {
        // Use df command to check available space
        std::process::Command::new("df")
            .args(["--output=avail", "-B1", "/"])
            .output()
            .ok()
            .and_then(|output| {
                let stdout = String::from_utf8_lossy(&output.stdout);
                stdout.lines()
                    .nth(1) // Skip header
                    .and_then(|line| line.trim().parse().ok())
            })
    }

    /// Run a script in an external terminal (Konsole) for full interactivity
    /// Returns immediately after launching, terminal stays open after script completes
    pub async fn run(
        &self,
        script: &ScriptMeta,
        operation: &Operation,
    ) -> mpsc::Receiver<ScriptOutput> {
        let (tx, rx) = mpsc::channel(100);
        
        let script_path = self.cfg.scripts_dir.join(&script.filename);
        let args = operation.to_args();
        let script_name = script.name.to_string();
        let env_log_dir = self.cfg.log_dir.clone();
        let env_backup_dir = self.cfg.backup_dir.clone();
        let env_data_dir = self.cfg.data_dir.clone();
        
        tokio::spawn(async move {
            // Build the command string for the terminal
            let mut script_cmd = format!("bash '{}'", script_path.display());
            for arg in &args {
                script_cmd.push_str(&format!(" '{}'", arg));
            }
            
            // Log file for GUI output mirroring
            let log_file = env_log_dir.join(format!("{}_terminal.log", 
                script_path.file_stem().unwrap_or_default().to_string_lossy()));
            
            // Clear any existing log file
            let _ = std::fs::write(&log_file, "");
            
            // Build the inner shell command (shared across all terminals)
            let inner_cmd = format!(
                "export DEBIAN_TOOLS_LOG_DIR='{}'; \
                 export DEBIAN_TOOLS_BACKUP_DIR='{}'; \
                 export DEBIAN_TOOLS_DATA_DIR='{}'; \
                 script -q -f -e -c \"{}\" '{}'; \
                 echo -e '\\nPress any key to close terminal...'; \
                 read -n 1 -s -r",
                env_log_dir.display(),
                env_backup_dir.display(),
                env_data_dir.display(),
                script_cmd,
                log_file.display()
            );
            
            // Detect available terminal emulator
            let terminal = Self::detect_terminal();
            
            let result = match terminal.as_str() {
                "konsole" => {
                    Command::new("konsole")
                        .arg("-e")
                        .arg("bash")
                        .arg("-c")
                        .arg(&inner_cmd)
                        .spawn()
                }
                "gnome-terminal" => {
                    Command::new("gnome-terminal")
                        .arg("--")
                        .arg("bash")
                        .arg("-c")
                        .arg(&inner_cmd)
                        .spawn()
                }
                _ => {
                    // Fallback: xterm
                    Command::new("xterm")
                        .arg("-e")
                        .arg("bash")
                        .arg("-c")
                        .arg(&inner_cmd)
                        .spawn()
                }
            };
            
            match result {
                Ok(mut child) => {
                    let _ = tx.send(ScriptOutput::Line(
                        format!("▶ Launched {} in external terminal", script_name)
                    )).await;
                    let _ = tx.send(ScriptOutput::Line(
                        format!("📄 Log file: {}", log_file.display())
                    )).await;
                    
                    // Give the terminal a moment to start and create the log file
                    tokio::time::sleep(Duration::from_millis(500)).await;
                    
                    // Tail the log file to stream output to GUI
                    if let Ok(file) = File::open(&log_file).await {
                        let mut reader = BufReader::new(file);
                        let mut line = String::new();
                        
                        // Read existing content first
                        loop {
                            match reader.read_line(&mut line).await {
                                Ok(0) => {
                                    // No more data available right now
                                    // Check if terminal is still running
                                    match child.try_wait() {
                                        Ok(Some(_status)) => {
                                            // Terminal exited, read any remaining content
                                            while reader.read_line(&mut line).await.unwrap_or(0) > 0 {
                                                let trimmed = line.trim_end().to_string();
                                                if !trimmed.is_empty() {
                                                    let _ = tx.send(ScriptOutput::Line(trimmed)).await;
                                                }
                                                line.clear();
                                            }
                                            break;
                                        }
                                        Ok(None) => {
                                            // Still running, wait and try again
                                            tokio::time::sleep(Duration::from_millis(100)).await;
                                        }
                                        Err(_) => break,
                                    }
                                }
                                Ok(_) => {
                                    let trimmed = line.trim_end().to_string();
                                    if !trimmed.is_empty() {
                                        let _ = tx.send(ScriptOutput::Line(trimmed)).await;
                                    }
                                    line.clear();
                                }
                                Err(_) => break,
                            }
                        }
                    }
                    
                    let _ = tx.send(ScriptOutput::Finished { success: true, code: Some(0) }).await;
                }
                Err(e) => {
                    let _ = tx.send(ScriptOutput::Error(
                        format!("Failed to launch terminal: {}. Install konsole, gnome-terminal, or xterm.", e)
                    )).await;
                }
            }
        });

        rx
    }
    
    /// Detect available terminal emulator
    fn detect_terminal() -> String {
        // Prefer konsole for KDE, then gnome-terminal, then xterm
        for term in &["konsole", "gnome-terminal", "xterm"] {
            if std::process::Command::new("which")
                .arg(term)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
            {
                return term.to_string();
            }
        }
        "xterm".to_string()
    }
}
