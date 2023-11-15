//! Debian Tools GUI - Main Application
//!
//! A graphical interface for debian-tools scripts built with iced.

mod components;
mod config;
mod scripts;
mod theme;
mod views;
mod embedded_scripts;

use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use iced::widget::{container, row};
use iced::futures::SinkExt;
use iced::{Element, Length, Task};

use config::{Config, Preferences, ThemePreference};
use components::sidebar::sidebar;
use components::terminal::terminal_panel;
use scripts::{Category, Operation, ScriptRegistry};
use scripts::runner::{RunnerConfig, ScriptOutput, ScriptRunner};
use theme::AppTheme;
use views::category::category_view;

fn main() -> iced::Result {
    iced::application("Debian Tools", App::update, App::view)
        .theme(|app| app.theme.to_iced_theme())
        .window_size((1000.0, 700.0))
        .run_with(App::new)
}

/// Queued script for batch operations
#[derive(Debug, Clone)]
struct QueuedScript {
    script_id: String,
    operation: Operation,
}

struct App {
    theme: AppTheme,
    current_category: Category,
    registry: ScriptRegistry,
    scripts_dir: PathBuf,
    log_dir: PathBuf,
    backup_dir: PathBuf,
    data_dir: PathBuf,
    runner: Arc<ScriptRunner>,
    terminal_output: Vec<String>,
    running_script: Option<String>,
    script_start_time: Option<Instant>,
    // Batch queue
    script_queue: VecDeque<QueuedScript>,
    // Script panel collapse state
    script_panel_collapsed: bool,
}

#[derive(Debug, Clone)]
pub enum Message {
    SelectCategory(Category),
    ToggleTheme,
    OpenLogs,
    CopyOutput,
    ClearOutput,
    CancelScript,
    RunScript { script_id: String, operation: Operation },
    QueueScript { script_id: String, operation: Operation },
    RemoveFromQueue(usize),
    ToggleScriptPanel,  // index to remove
    RunBatch,
    ClearQueue,
    // Streaming output messages
    ScriptOutputLine(String),
    ScriptFinished { success: bool, name: String },
}

impl App {
    fn new() -> (Self, Task<Message>) {
        let cfg = Config::load();
        let prefs = Preferences::load();

        let scripts_dir = resolve_scripts_dir(&cfg);

        // Resolve data directories (logs, backups) relative to scripts directory
        // Matches common.sh behavior: repo-relative by default, env variables override
        let (log_dir, backup_dir, data_dir) = resolve_data_dirs(&cfg, &scripts_dir);

        let runner = Arc::new(ScriptRunner::new(RunnerConfig {
            scripts_dir: scripts_dir.clone(),
            log_dir: log_dir.clone(),
            backup_dir: backup_dir.clone(),
            data_dir: data_dir.clone(),
            default_timeout_minutes: cfg.default_timeout_minutes,
            check_network: cfg.check_network,
            check_disk_space: cfg.check_disk_space,
        }));

        let theme = match prefs.theme {
            ThemePreference::Light => AppTheme::light(),
            ThemePreference::Dark => AppTheme::dark(),
            ThemePreference::System => AppTheme::dark(), // iced 0.13: keep simple for now
        };

        let current_category = prefs
            .last_category
            .as_deref()
            .and_then(Category::try_from_str)
            .unwrap_or(Category::Security);

        (
            Self {
                theme,
                current_category,
                registry: ScriptRegistry::new_from_path(&scripts_dir),
                scripts_dir,
                log_dir,
                backup_dir,
                data_dir,
                runner,
                terminal_output: vec![
                    "Welcome to Debian Tools GUI".into(),
                    "Select a script to run, or queue multiple for batch.".into(),
                ],
                running_script: None,
                script_start_time: None,
                script_queue: VecDeque::new(),
                script_panel_collapsed: false,
            },
            Task::none(),
        )
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectCategory(cat) => {
                self.current_category = cat;
                
                // Save preference
                let mut prefs = Preferences::load();
                prefs.last_category = Some(cat.name().to_lowercase());
                let _ = prefs.save();
                
                Task::none()
            }
            Message::ToggleTheme => {
                self.theme = if self.theme.dark {
                    AppTheme::light()
                } else {
                    AppTheme::dark()
                };
                
                // Save preference
                let mut prefs = Preferences::load();
                prefs.theme = if self.theme.dark {
                    ThemePreference::Dark
                } else {
                    ThemePreference::Light
                };
                let _ = prefs.save();
                
                Task::none()
            }
            Message::OpenLogs => {
                let log_dir = self.log_dir.clone();
                
                self.terminal_output.push(format!("Log directory: {}", log_dir.display()));
                
                if let Err(e) = std::process::Command::new("xdg-open")
                    .arg(&log_dir)
                    .spawn()
                {
                    self.terminal_output.push(format!("[ERR] Failed to open: {}", e));
                }
                Task::none()
            }
            Message::CopyOutput => {
                let output_text = self.terminal_output.join("\n");
                
                use std::io::Write;
                if let Ok(mut child) = std::process::Command::new("xclip")
                    .args(["-selection", "clipboard"])
                    .stdin(std::process::Stdio::piped())
                    .spawn()
                {
                    if let Some(mut stdin) = child.stdin.take() {
                        let _ = stdin.write_all(output_text.as_bytes());
                    }
                    self.terminal_output.push("✓ Copied to clipboard".into());
                } else if let Ok(mut child) = std::process::Command::new("wl-copy")
                    .stdin(std::process::Stdio::piped())
                    .spawn()
                {
                    if let Some(mut stdin) = child.stdin.take() {
                        let _ = stdin.write_all(output_text.as_bytes());
                    }
                    self.terminal_output.push("✓ Copied to clipboard".into());
                } else {
                    self.terminal_output.push("[ERR] Install xclip or wl-copy".into());
                }
                Task::none()
            }
            Message::ClearOutput => {
                self.terminal_output.clear();
                self.terminal_output.push("Output cleared.".into());
                Task::none()
            }
            Message::CancelScript => {
                // Scripts now run in external terminal - user can close terminal to cancel
                self.terminal_output.push("ℹ To cancel, close the terminal window running the script".into());
                Task::none()
            }
            Message::QueueScript { script_id, operation } => {
                // Check for duplicates (both script_id AND operation)
                let already_queued = self.script_queue.iter()
                    .any(|q| q.script_id == script_id && q.operation == operation);
                
                if already_queued {
                    self.terminal_output.push(format!("[WARN] {} ({}) already in queue", script_id, operation.label()));
                    return Task::none();
                }
                
                if let Some(script) = self.registry.get(&script_id) {
                    self.script_queue.push_back(QueuedScript {
                        script_id: script_id.clone(),
                        operation: operation.clone(),
                    });
                    self.terminal_output.push(format!(
                        "📋 Queued: {} ({})",
                        script.name,
                        operation.label()
                    ));
                }
                Task::none()
            }
            Message::RemoveFromQueue(index) => {
                if index < self.script_queue.len() {
                    if let Some(removed) = self.script_queue.remove(index) {
                        self.terminal_output.push(format!("Removed: {}", removed.script_id));
                    }
                }
                Task::none()
            }
            Message::ClearQueue => {
                self.script_queue.clear();
                self.terminal_output.push("📋 Queue cleared".into());
                Task::none()
            }
            Message::ToggleScriptPanel => {
                self.script_panel_collapsed = !self.script_panel_collapsed;
                Task::none()
            }
            Message::RunBatch => {
                if self.script_queue.is_empty() {
                    self.terminal_output.push("[WARN] Queue is empty".into());
                    return Task::none();
                }
                if self.running_script.is_some() {
                    self.terminal_output.push("[WARN] A script is already running".into());
                    return Task::none();
                }
                // Start first script from queue
                if let Some(queued) = self.script_queue.pop_front() {
                    return self.start_script(&queued.script_id, &queued.operation);
                }
                Task::none()
            }
            Message::RunScript { script_id, operation } => {
                if self.running_script.is_some() {
                    self.terminal_output.push("[WARN] A script is already running".into());
                    return Task::none();
                }
                self.start_script(&script_id, &operation)
            }
            Message::ScriptOutputLine(line) => {
                self.terminal_output.push(line);
                
                // Keep terminal manageable
                if self.terminal_output.len() > 500 {
                    self.terminal_output.drain(0..100);
                }
                
                Task::none()
            }
            Message::ScriptFinished { success, name } => {
                // Calculate duration
                let duration = self.script_start_time
                    .map(|t| t.elapsed().as_secs())
                    .unwrap_or(0);
                
                self.running_script = None;
                self.script_start_time = None;
                
                if success {
                    self.terminal_output.push(format!("✓ {} completed in {}s", name, duration));
                } else {
                    self.terminal_output.push(format!("✗ {} failed", name));
                }
                
                // Desktop notification for scripts > 5 seconds
                if duration > 5 {
                    let msg = if success {
                        format!("{} completed successfully", name)
                    } else {
                        format!("{} failed", name)
                    };
                    let _ = std::process::Command::new("notify-send")
                        .args(["-a", "Debian Tools", &msg])
                        .spawn();
                }
                
                // Continue with queue if not empty
                if let Some(queued) = self.script_queue.pop_front() {
                    self.terminal_output.push(format!("─── Next: {} ───", queued.script_id));
                    return self.start_script(&queued.script_id, &queued.operation);
                }
                
                Task::none()
            }
        }
    }

    fn start_script(&mut self, script_id: &str, operation: &Operation) -> Task<Message> {
        if let Some(script) = self.registry.get(script_id) {
            // Pre-execution validation
            use scripts::runner::PreCheckResult;
            match self.runner.pre_check(&script) {
                PreCheckResult::Ok => {}
                PreCheckResult::NetworkUnavailable => {
                    self.terminal_output.push("⚠ Network unavailable. This script requires internet.".into());
                    return Task::none();
                }
                PreCheckResult::ScriptNotFound(path) => {
                    self.terminal_output.push(format!("✗ Script not found: {}", path.display()));
                    return Task::none();
                }
                PreCheckResult::DiskSpaceLow(bytes) => {
                    let mb = bytes / (1024 * 1024);
                    self.terminal_output.push(format!("⚠ Low disk space: {}MB available. Continuing anyway...", mb));
                    // Continue but warn
                }
            }

            let script_name = script.name.to_string();
            self.running_script = Some(script_name.clone());
            self.script_start_time = Some(Instant::now());
            self.terminal_output.push(format!(
                "▶ Running: {} {}",
                script.filename,
                operation.to_args().join(" ")
            ));

            let runner = Arc::clone(&self.runner);
            let script_meta = script.clone();
            let op = operation.clone();
            let name = script_name.clone();

            // Use Task::run with a stream for real-time output
            return Task::run(
                iced::stream::channel(100, move |mut sender| async move {
                    let mut rx = runner.run(&script_meta, &op).await;
                    let mut success = true;

                    while let Some(output) = rx.recv().await {
                        match output {
                            ScriptOutput::Line(line) => {
                                let _ = sender.send(Message::ScriptOutputLine(line)).await;
                            }
                            ScriptOutput::Finished { success: s, .. } => {
                                success = s;
                                break;
                            }
                            ScriptOutput::Error(e) => {
                                let _ = sender.send(Message::ScriptOutputLine(format!("[ERR] {}", e))).await;
                                success = false;
                                break;
                            }
                            ScriptOutput::Cancelled => {
                                let _ = sender.send(Message::ScriptOutputLine("⏹ Script cancelled by user".into())).await;
                                success = false;
                                break;
                            }
                            ScriptOutput::Timeout => {
                                let _ = sender.send(Message::ScriptOutputLine("⏱ Script timed out".into())).await;
                                success = false;
                                break;
                            }
                        }
                    }

                    // Send completion message
                    let _ = sender.send(Message::ScriptFinished { success, name }).await;
                }),
                std::convert::identity,
            );
        }
        Task::none()
    }

    fn view(&self) -> Element<'_, Message> {
        let sidebar = sidebar(self.current_category, &self.theme);
        // Pass actual queue data for checking
        let queue_data: Vec<(String, Operation)> = self.script_queue.iter()
            .map(|q| (q.script_id.clone(), q.operation.clone()))
            .collect();
        
        let content = category_view(
            self.current_category,
            &self.registry,
            &self.theme,
            self.running_script.is_some(),
            &queue_data,
            self.script_panel_collapsed,  // Pass collapse state
        );
        let terminal = terminal_panel(
            &self.terminal_output,
            self.running_script.as_deref(),
            &self.theme,
        );
        
        // Layout: sidebar (140px) | scripts (fixed 380px) | terminal (fills rest)
        // Wrap terminal in a container to ensure it fills remaining space
        let terminal_wrapper = container(terminal)
            .width(Length::Fill)
            .height(Length::Fill);
        
        let main_area = row![content, terminal_wrapper]
            .spacing(8)
            .width(Length::Fill)
            .height(Length::Fill);

        let layout = row![sidebar, main_area]
            .width(Length::Fill);

        container(layout)
            .width(Length::Fill)
            .height(Length::Fill)
            .style(move |_| iced::widget::container::Style {
                background: Some(self.theme.background().into()),
                ..Default::default()
            })
            .into()
    }
}

fn is_scripts_dir(path: &PathBuf) -> bool {
    path.join("utils").join("common.sh").exists()
}

fn resolve_scripts_dir(cfg: &Config) -> PathBuf {
    // HYBRID APPROACH: Use embedded scripts in release builds only
    #[cfg(not(debug_assertions))]
    {
        if embedded_scripts::should_use_embedded() {
            match embedded_scripts::extract_scripts() {
                Ok(cache_dir) => {
                    eprintln!("Using embedded scripts from cache");
                    return cache_dir;
                }
                Err(e) => {
                    eprintln!("Warning: Failed to extract embedded scripts: {}", e);
                    eprintln!("Falling back to filesystem lookup...");
                }
            }
        }
    }
    
    // Development mode or fallback: use scripts from disk
    #[cfg(debug_assertions)]
    eprintln!("Development mode: using scripts from disk");
    
    // 1) Config/env override
    if let Some(dir) = cfg.get_scripts_dir() {
        if is_scripts_dir(&dir) {
            return dir;
        }
    }

    // 2) Walk up from current executable
    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Ok(exe) = std::env::current_exe().and_then(|p| p.canonicalize()) {
        let mut cur = exe.parent().map(|p| p.to_path_buf());
        for _ in 0..10 {
            if let Some(p) = cur.take() {
                candidates.push(p.join("scripts"));
                candidates.push(p.join("debian-tools").join("scripts"));
                cur = p.parent().map(|p| p.to_path_buf());
            } else {
                break;
            }
        }
    }

    for c in candidates {
        if is_scripts_dir(&c) {
            return c;
        }
    }

    // 3) Fallback
    PathBuf::from("scripts")
}


fn resolve_data_dirs(cfg: &Config, scripts_dir: &PathBuf) -> (PathBuf, PathBuf, PathBuf) {
    // Simplified logic to match common.sh behavior:
    // 1. Environment variables override everything
    // 2. Otherwise, use repo-relative paths (scripts_dir parent = repo root)
    
    let data_dir = cfg.get_data_dir();

    // Check for explicit environment overrides
    let explicit_log = cfg.log_dir.is_some()
        || std::env::var("DEBIAN_TOOLS_LOG_DIR").is_ok()
        || std::env::var("DT_LOG_DIR").is_ok();
    let explicit_backup = cfg.backup_dir.is_some()
        || std::env::var("DEBIAN_TOOLS_BACKUP_DIR").is_ok()
        || std::env::var("DT_BACKUP_DIR").is_ok();

    // Repository root is the parent of scripts_dir
    let repo_root = scripts_dir.parent().unwrap_or(scripts_dir);

    // Default to repo-relative paths, matching common.sh behavior
    let log_dir = if explicit_log {
        cfg.get_log_dir()
    } else {
        repo_root.join("logs")
    };

    let backup_dir = if explicit_backup {
        cfg.get_backup_dir()
    } else {
        repo_root.join("backups")
    };

    // Ensure directories exist (best-effort; scripts also mkdir -p)
    let _ = std::fs::create_dir_all(&log_dir);
    let _ = std::fs::create_dir_all(&backup_dir);
    let _ = std::fs::create_dir_all(&data_dir);

    (log_dir, backup_dir, data_dir)
}
