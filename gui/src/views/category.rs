//! Category view - compact grid with visible queue list

use iced::widget::{button, column, container, row, scrollable, text, Column};
use iced::{Element, Length};

use crate::components::script_card::script_card;
use crate::scripts::{Category, Operation, ScriptRegistry};
use crate::scripts::status::check_installed;
use crate::theme::{AppTheme, TEXT_SM, TEXT_MD, TEXT_LG, SPACE_XS, SPACE_SM, SPACE_MD, RADIUS_SM, QUEUE_MAX_HEIGHT, SCRIPT_PANEL_WIDTH};
use crate::Message;

pub fn category_view<'a>(
    category: Category,
    registry: &ScriptRegistry,
    theme: &'a AppTheme,
    is_running: bool,
    queue_data: &[(String, Operation)],  // (script_id, operation)
    script_panel_collapsed: bool,  // NEW: collapse state
) -> Element<'a, Message> {
    let scripts = registry.by_category(category);

    // Header with category name, collapse button, and queue controls
    let collapse_icon = if script_panel_collapsed { "▶" } else { "◀" };
    let header_text = text(format!("{} {}", category.icon(), category.name()))
        .size(TEXT_LG)
        .color(theme.text()); // Added .color(theme.text()) to match original header_text styling
    
    let collapse_btn = button(text(collapse_icon).size(TEXT_MD))
        .padding([SPACE_XS, SPACE_SM])
        .style(button::text)
        .on_press(Message::ToggleScriptPanel);
    
    let run_batch_btn = button(text("Run Queue").size(TEXT_SM))
        .padding([SPACE_XS, SPACE_SM])
        .style(if !queue_data.is_empty() && !is_running { button::primary } else { button::secondary })
        .on_press_maybe(if !queue_data.is_empty() && !is_running { 
            Some(Message::RunBatch) 
        } else { 
            None 
        });
    
    let clear_queue_btn = button(text("Clear All").size(TEXT_SM))
        .padding([SPACE_XS, SPACE_SM])
        .style(button::text)
        .on_press_maybe(if !queue_data.is_empty() { Some(Message::ClearQueue) } else { None });

    let header = row![
        header_text,
        collapse_btn,
        run_batch_btn,
        clear_queue_btn,
        iced::widget::horizontal_space(),
    ]
    .spacing(SPACE_SM)
    .align_y(iced::Alignment::Center);

    // Queue list (vertical column with scrolling)
    let queue_section = if queue_data.is_empty() {
        // Show empty state hint
        Column::new()
            .push(text("Queue is empty - click + to add scripts").size(TEXT_SM).color(theme.text_secondary()))
            .spacing(SPACE_XS)
    } else {
        let mut queue_list = Column::new().spacing(SPACE_SM);
        
        for (idx, (script_id, operation)) in queue_data.iter().enumerate() {
            let name = registry.get(script_id)
                .map(|s| s.name.clone())
                .unwrap_or_else(|| script_id.to_string());
                
            let item = row![
                text(format!("{}. {} ({})", idx + 1, name, operation.label()))
                    .size(TEXT_SM)
                    .color(iced::color!(0x9b59b6)),
                iced::widget::horizontal_space(),
                button(text("×").size(TEXT_SM))
                    .padding([SPACE_XS / 2.0, SPACE_XS])
                    .style(button::text)
                    .on_press(Message::RemoveFromQueue(idx)),
            ]
            .spacing(SPACE_XS)
            .align_y(iced::Alignment::Center);
            
            queue_list = queue_list.push(
                container(item)
                    .width(Length::Fill)
                    .padding([SPACE_XS, SPACE_SM])
                    .style(move |_| iced::widget::container::Style {
                        background: Some(if theme.dark {
                            iced::color!(0x2d2d44)
                        } else {
                            iced::color!(0xe8e4f3)
                        }.into()),
                        border: iced::Border {
                            radius: RADIUS_SM.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    })
            );
        }
        
        Column::new()
            .push(text(format!("Queue ({})", queue_data.len())).size(TEXT_SM).color(iced::color!(0x9b59b6)))
            .push(
                scrollable(queue_list)
                    .height(Length::Fixed(QUEUE_MAX_HEIGHT))  // Max height ~half viewport
                    .direction(scrollable::Direction::Vertical(
                        scrollable::Scrollbar::new()
                    ))
            )
            .spacing(SPACE_XS)
    };

    // Script list (vertical column, not grid)
    let mut script_list = Column::new().spacing(8);

    for script in scripts {
        let installed = check_installed(script);
        script_list = script_list.push(script_card(script, installed, theme, is_running, queue_data));
    }

    // Conditional rendering based on collapse state
    if script_panel_collapsed {
        // When collapsed: return minimal/hidden container
        container(column![])
            .width(Length::Shrink)
            .height(Length::Fill)
            .into()
    } else {
        // When expanded: render full content with header, queue, and scripts
        let content = column![header, queue_section, script_list]
            .spacing(SPACE_SM)
            .padding(SPACE_MD);

        let scrollable_content = scrollable(content)
            .width(Length::Fixed(SCRIPT_PANEL_WIDTH))
            .height(Length::Fill);

        container(scrollable_content)
            .width(Length::Fixed(SCRIPT_PANEL_WIDTH))
            .height(Length::Fill)
            .into()
    }
}
