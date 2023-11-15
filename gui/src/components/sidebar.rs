//! Sidebar navigation - compact design

use iced::widget::{button, container, text, Column};
use iced::{Element, Length};

use crate::scripts::Category;
use crate::theme::{sidebar_style, AppTheme, TEXT_MD, SPACE_XS, SPACE_SM, SPACE_MD, SIDEBAR_WIDTH};
use crate::Message;

pub fn sidebar<'a>(
    current: Category,
    theme: &'a AppTheme,
) -> Element<'a, Message> {
    let mut items = Column::new().spacing(SPACE_XS).padding(SPACE_SM);

    for category in Category::all() {
        let is_selected = *category == current;
        let label = format!("{} {}", category.icon(), category.name());

        let btn = button(text(label).size(TEXT_MD))
            .width(Length::Fill)
            .padding([SPACE_SM, SPACE_MD])
            .style(if is_selected {
                button::primary
            } else {
                button::text
            })
            .on_press(Message::SelectCategory(*category));

        items = items.push(btn);
    }

    // Spacer
    items = items.push(iced::widget::vertical_space().height(Length::Fill));
    
    // Utility buttons
    items = items.push(
        button(text("Logs").size(TEXT_MD))
            .width(Length::Fill)
            .padding([SPACE_SM, SPACE_MD])
            .style(button::text)
            .on_press(Message::OpenLogs),
    );

    items = items.push(
        button(text(if theme.dark { "Light" } else { "Dark" }).size(TEXT_MD))
            .width(Length::Fill)
            .padding([SPACE_SM, SPACE_MD])
            .style(button::text)
            .on_press(Message::ToggleTheme),
    );

    container(items)
        .width(SIDEBAR_WIDTH)
        .height(Length::Fill)
        .style(move |_| sidebar_style(theme))
        .into()
}
