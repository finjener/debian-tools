use iced::widget::{button, column, container, row, scrollable, text, Column};
use iced::{Element, Length};

use crate::theme::{AppTheme, TEXT_SM, TEXT_MD, SPACE_XS, SPACE_SM, RADIUS_SM};
use crate::Message;

pub fn terminal_panel<'a>(
    lines: &'a [String],
    running_script: Option<&str>,
    theme: &'a AppTheme,
) -> Element<'a, Message> {
    let mut output = Column::new().spacing(1);

    for line in lines {
        let color = if line.starts_with("[ERR]") || line.contains("ERROR") || line.starts_with("✗") {
            theme.danger()
        } else if line.contains("✓") || line.contains("[OK]") || line.contains("completed") {
            theme.success()
        } else if line.contains("⚠") || line.contains("[WARN]") || line.contains("Warning") {
            theme.warning()
        } else if line.starts_with("▶") || line.starts_with("───") {
            theme.accent()
        } else if line.starts_with("📋") {
            iced::color!(0x9b59b6) // Purple for queued
        } else {
            theme.text()
        };

        output = output.push(text(line).size(TEXT_MD).color(color));
    }

    let scrollable_content = scrollable(output)
        .width(Length::Fill)
        .height(Length::Fill);  // Fill available height instead of fixed 120px

    // Spinner for running state
    let status_text = if let Some(script) = running_script {
        text(format!("⟳ Running: {}", script))
            .size(TEXT_MD)
            .color(theme.accent())
    } else {
        text("Output")
            .size(TEXT_MD)
            .color(theme.text_secondary())
    };

    // Header with buttons
    let cancel_btn = if running_script.is_some() {
        button(text("⏹ Stop").size(TEXT_SM))
            .padding([SPACE_XS, SPACE_SM])
            .style(button::danger)
            .on_press(Message::CancelScript)
    } else {
        button(text("⏹ Stop").size(TEXT_SM))
            .padding([SPACE_XS, SPACE_SM])
            .style(button::secondary)
            // Disabled when not running - no on_press
    };

    let header = row![
        status_text,
        iced::widget::horizontal_space(),
        cancel_btn,
        button(text("Clear").size(TEXT_SM))
            .padding([SPACE_XS, SPACE_SM])
            .style(button::text)
            .on_press(Message::ClearOutput),
        button(text("Copy").size(TEXT_SM))
            .padding([SPACE_XS, SPACE_SM])
            .style(button::secondary)
            .on_press(Message::CopyOutput),
    ]
    .spacing(6)
    .align_y(iced::Alignment::Center);

    let content = column![header, scrollable_content]
        .spacing(SPACE_XS)
        .padding(SPACE_SM);

    container(content)
        .width(Length::Fill)  // Fill all remaining space after fixed-width script panel
        .height(Length::Fill)
        .height(Length::Fill)
        .style(move |_| iced::widget::container::Style {
            background: Some(if theme.dark {
                iced::color!(0x1e1e2e)
            } else {
                iced::color!(0xffffff)
            }.into()),
            border: iced::Border {
                color: if theme.dark {
                    iced::color!(0x45475a)
                } else {
                    iced::color!(0xbdc3c7)
                },
                width: 1.0,
                radius: RADIUS_SM.into(),
            },
            ..Default::default()
        })
        .into()
}
