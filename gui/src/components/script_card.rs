//! Script card component - compact modern design with queue support

use iced::widget::{button, column, container, row, text, Column};
use iced::Element;

use crate::scripts::{Operation, ScriptMeta, ScriptType};
use crate::theme::{card_style, AppTheme, TEXT_XS, TEXT_SM, TEXT_MD, SPACE_XS, SPACE_SM, SPACE_MD};
use crate::Message;

pub fn script_card<'a>(
    script: &ScriptMeta,
    installed: Option<bool>,
    theme: &'a AppTheme,
    is_running: bool,
    queue_data: &[(String, Operation)],
) -> Element<'a, Message> {
    // Status dot
    let status_dot = match installed {
        Some(true) => text("●").size(TEXT_XS).color(theme.success()),
        Some(false) => text("○").size(TEXT_XS).color(theme.text_secondary()),
        None => text("").size(TEXT_XS),
    };

    let title = row![
        status_dot,
        text(script.name.clone()).size(TEXT_MD),
    ]
    .spacing(SPACE_XS)
    .align_y(iced::Alignment::Center);

    let actions = build_actions(script, installed, is_running, queue_data);

    let content = column![title, actions]
        .spacing(SPACE_SM)
        .padding(SPACE_MD);

    container(content)
        .width(170)
        .style(move |_| card_style(theme))
        .into()
}

fn build_actions<'a>(
    script: &ScriptMeta,
    installed: Option<bool>,
    is_running: bool,
    queue_data: &[(String, Operation)],
) -> Column<'a, Message> {
    let mut actions = Column::new().spacing(SPACE_XS);

    match script.script_type {
        ScriptType::BackupRestore => {
            // Backup button with + queue toggle
            let backup_queued = queue_data.iter()
                .any(|(id, op)| id == &script.id && matches!(op, Operation::Backup));
            
            actions = actions.push(row![
                action_btn("Backup", button::primary, is_running, Message::RunScript {
                    script_id: script.id.to_string(),
                    operation: Operation::Backup,
                }),
                queue_toggle_btn(
                    backup_queued,
                    is_running,
                    &script.id,
                    Operation::Backup,
                    queue_data,
                ),
            ].spacing(SPACE_XS));
            
            // Restore button with +/- queue toggle
            let restore_queued = queue_data.iter()
                .any(|(id, op)| id == &script.id && matches!(op, Operation::RestoreInteractive));
            
            actions = actions.push(row![
                action_btn("Restore", button::secondary, is_running, Message::RunScript {
                    script_id: script.id.to_string(),
                    operation: Operation::RestoreInteractive,
                }),
                queue_toggle_btn(
                    restore_queued,
                    is_running,
                    &script.id,
                    Operation::RestoreInteractive,
                    queue_data,
                ),
            ].spacing(SPACE_XS));
        }
        ScriptType::InstallUninstall => {
            if installed == Some(true) {
                let queued = queue_data.iter()
                    .any(|(id, op)| id == &script.id && matches!(op, Operation::Uninstall));
                
                actions = actions.push(row![
                    action_btn("Uninstall", button::danger, is_running, Message::RunScript {
                        script_id: script.id.to_string(),
                        operation: Operation::Uninstall,
                    }),
                    queue_toggle_btn(
                        queued,
                        is_running,
                        &script.id,
                        Operation::Uninstall,
                        queue_data,
                    ),
                ].spacing(SPACE_XS));
            } else {
                let queued = queue_data.iter()
                    .any(|(id, op)| id == &script.id && matches!(op, Operation::Install));
                
                actions = actions.push(row![
                    action_btn("Install", button::primary, is_running, Message::RunScript {
                        script_id: script.id.to_string(),
                        operation: Operation::Install,
                    }),
                    queue_toggle_btn(
                        queued,
                        is_running,
                        &script.id,
                        Operation::Install,
                        queue_data,
                    ),
                ].spacing(SPACE_XS));
            }
        }
        ScriptType::PackageManager => {
            let queued = queue_data.iter()
                .any(|(id, op)| id == &script.id && matches!(op, Operation::Install));
            
            actions = actions.push(row![
                action_btn("Install", button::primary, is_running, Message::RunScript {
                    script_id: script.id.to_string(),
                    operation: Operation::Install,
                }),
                action_btn("Sim", button::secondary, is_running, Message::RunScript {
                    script_id: script.id.to_string(),
                    operation: Operation::Simulate,
                }),
                queue_toggle_btn(
                    queued,
                    is_running,
                    &script.id,
                    Operation::Install,
                    queue_data,
                ),
            ].spacing(SPACE_XS));
        }
        ScriptType::Configure => {
            let queued = queue_data.iter()
                .any(|(id, op)| id == &script.id && matches!(op, Operation::Configure));
            
            actions = actions.push(row![
                action_btn("Configure", button::primary, is_running, Message::RunScript {
                    script_id: script.id.to_string(),
                    operation: Operation::Configure,
                }),
                queue_toggle_btn(
                    queued,
                    is_running,
                    &script.id,
                    Operation::Configure,
                    queue_data,
                ),
            ].spacing(SPACE_XS));
        }
        ScriptType::Interactive => {
            actions = actions.push(text("Terminal").size(TEXT_SM).color(iced::color!(0x888888)));
        }
    }

    actions
}

fn action_btn<'a>(
    label: &'a str,
    style: fn(&iced::Theme, button::Status) -> button::Style,
    is_running: bool,
    msg: Message,
) -> iced::widget::Button<'a, Message> {
    let btn = button(text(label).size(TEXT_SM))
        .padding([SPACE_XS, SPACE_SM])
        .style(style);
    
    if is_running {
        btn
    } else {
        btn.on_press(msg)
    }
}

// Compact queue toggle button (shows "+" or "-")
fn queue_toggle_btn<'a>(
    is_queued: bool,
    is_running: bool,
    script_id: &str,
    operation: Operation,
    queue_data: &[(String, Operation)],
) -> iced::widget::Button<'a, Message> {
    let label = if is_queued { "-" } else { "+" };
    
    let btn = button(text(label).size(TEXT_MD))  // Increased from TEXT_XS to TEXT_MD
        .padding([SPACE_XS, SPACE_SM])          // Increased padding for better visibility  
        .style(button::secondary);               // Changed to secondary for prominence
    
    if is_running {
        return btn;
    }
    
    if is_queued {
        // Find index and create remove message
        if let Some(idx) = queue_data.iter().position(|(id, op)| id == &script_id && op == &operation) {
            btn.on_press(Message::RemoveFromQueue(idx))
        } else {
            btn
        }
    } else {
        btn.on_press(Message::QueueScript {
            script_id: script_id.to_string(),
            operation,
        })
    }
}
