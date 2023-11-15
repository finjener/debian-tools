//! KDE Breeze-inspired theme

use iced::color;
use iced::widget::container;
use iced::{Border, Color, Theme};

// ============================================================================
// Design System Constants
// ============================================================================

/// Spacing scale based on 4px increments
/// Use these for padding, margins, and gaps to maintain visual consistency
pub const SPACE_XS: f32 = 4.0;   // Extra small spacing
pub const SPACE_SM: f32 = 8.0;   // Small spacing
pub const SPACE_MD: f32 = 12.0;  // Medium spacing (default for most components)
pub const SPACE_LG: f32 = 16.0;  // Large spacing
pub const SPACE_XL: f32 = 24.0;  // Extra large spacing
pub const SPACE_XXL: f32 = 32.0; // Extra extra large spacing

/// Typography scale for consistent text sizing
/// Always use these instead of arbitrary pixel values
pub const TEXT_XS: u16 = 10;  // Extra small text (use sparingly, e.g., badges)
pub const TEXT_SM: u16 = 11;  // Small text (minimum for body text)
pub const TEXT_MD: u16 = 12;  // Medium text (default body text)
pub const TEXT_LG: u16 = 14;  // Large text (section headers)
pub const TEXT_XL: u16 = 16;  // Extra large text (main headers)

/// Component sizing for buttons and interactive elements
/// Ensures comfortable tap/click targets
pub const BTN_HEIGHT_SM: f32 = 24.0;  // Small buttons (compact UI)
pub const BTN_HEIGHT_MD: f32 = 32.0;  // Standard buttons
pub const BTN_HEIGHT_LG: f32 = 40.0;  // Large buttons (primary actions)

/// Border radius for rounded corners
/// Use these for consistent corner rounding across the UI
pub const RADIUS_SM: f32 = 4.0;   // Small radius (badges, small elements)
pub const RADIUS_MD: f32 = 8.0;   // Medium radius (default for cards)
pub const RADIUS_LG: f32 = 12.0;  // Large radius (large panels)

/// Line height multipliers for text readability
/// Apply these to text components for proper vertical rhythm
pub const LINE_HEIGHT_TIGHT: f32 = 1.3;   // Compact lists, dense info
pub const LINE_HEIGHT_NORMAL: f32 = 1.5;  // Default for body text
pub const LINE_HEIGHT_RELAXED: f32 = 1.6; // Large text, headers

/// State constants for interaction feedback
pub const DISABLED_OPACITY: f32 = 0.5;  // Opacity for disabled elements

// ============================================================================
// Component Sizing
// ============================================================================

/// Component widths for consistent layout
pub const SIDEBAR_WIDTH: f32 = 140.0;        // Sidebar navigation width
pub const SCRIPT_PANEL_WIDTH: f32 = 380.0;   // Script list panel width
pub const QUEUE_MAX_HEIGHT: f32 = 200.0;     // Maximum height for queue list

// ============================================================================
// Theme
// ============================================================================

/// Custom theme colors
pub struct AppTheme {
    pub dark: bool,
}

impl AppTheme {
    pub fn dark() -> Self {
        Self { dark: true }
    }

    pub fn light() -> Self {
        Self { dark: false }
    }

    pub fn background(&self) -> Color {
        if self.dark {
            color!(0x1e1e2e) // Catppuccin-like dark
        } else {
            color!(0xeff0f1) // KDE light
        }
    }

    pub fn surface(&self) -> Color {
        if self.dark {
            color!(0x313244)
        } else {
            color!(0xfcfcfc)
        }
    }

    pub fn text(&self) -> Color {
        if self.dark {
            color!(0xcdd6f4)
        } else {
            color!(0x232627)
        }
    }

    pub fn text_secondary(&self) -> Color {
        if self.dark {
            color!(0xa6adc8)
        } else {
            color!(0x7f8c8d)
        }
    }

    pub fn accent(&self) -> Color {
        color!(0x3daee9) // KDE blue
    }

    pub fn success(&self) -> Color {
        color!(0x27ae60)
    }

    pub fn warning(&self) -> Color {
        color!(0xf39c12)
    }

    pub fn danger(&self) -> Color {
        color!(0xe74c3c)
    }

    pub fn sidebar_bg(&self) -> Color {
        if self.dark {
            color!(0x181825)
        } else {
            color!(0xe3e5e8)
        }
    }

    /// Hover state background color (subtle change from surface)
    pub fn hover_bg(&self) -> Color {
        if self.dark {
            color!(0x3a3a4d) // Slightly lighter than surface
        } else {
            color!(0xf5f5f5) // Slightly darker than surface
        }
    }

    /// Focus indicator color (always accent blue for consistency)
    pub fn focus_outline(&self) -> Color {
        self.accent()
    }

    pub fn to_iced_theme(&self) -> Theme {
        if self.dark {
            Theme::CatppuccinMocha
        } else {
            Theme::Light
        }
    }
}

impl Default for AppTheme {
    fn default() -> Self {
        Self::dark()
    }
}

/// Container style for cards
pub fn card_style(theme: &AppTheme) -> container::Style {
    container::Style {
        background: Some(theme.surface().into()),
        border: Border {
            color: if theme.dark {
                color!(0x45475a)
            } else {
                color!(0xbdc3c7)
            },
            width: 1.0,
            radius: RADIUS_MD.into(),
        },
        ..Default::default()
    }
}

/// Container style for sidebar
pub fn sidebar_style(theme: &AppTheme) -> container::Style {
    container::Style {
        background: Some(theme.sidebar_bg().into()),
        ..Default::default()
    }
}
