//! freedesktop Notifications client (served by Omarchy's notification daemon).

use std::collections::HashMap;
use zbus::zvariant::Value;

#[zbus::proxy(
    interface = "org.freedesktop.Notifications",
    default_service = "org.freedesktop.Notifications",
    default_path = "/org/freedesktop/Notifications"
)]
pub trait Notifications {
    #[allow(clippy::too_many_arguments)]
    fn notify(
        &self,
        app_name: &str,
        replaces_id: u32,
        app_icon: &str,
        summary: &str,
        body: &str,
        actions: &[&str],
        hints: HashMap<&str, Value<'_>>,
        expire_timeout: i32,
    ) -> zbus::Result<u32>;

    fn close_notification(&self, id: u32) -> zbus::Result<()>;

    #[zbus(signal)]
    fn action_invoked(&self, id: u32, action_key: String) -> zbus::Result<()>;

    #[zbus(signal)]
    fn notification_closed(&self, id: u32, reason: u32) -> zbus::Result<()>;
}

pub struct Toast<'a> {
    pub app: &'a str,
    pub summary: &'a str,
    pub body: &'a str,
    pub urgency: u8,
    pub positive: Option<&'a str>,
    pub negative: Option<&'a str>,
}

pub async fn show(n: &NotificationsProxy<'_>, replaces: u32, t: &Toast<'_>) -> zbus::Result<u32> {
    let mut actions = Vec::new();
    if let Some(p) = t.positive {
        actions.extend(["positive", p]);
    }
    if let Some(neg) = t.negative {
        actions.extend(["negative", neg]);
    }
    let mut hints = HashMap::new();
    hints.insert("urgency", Value::U8(t.urgency));
    hints.insert("desktop-entry", Value::from("omarchy-delight"));
    hints.insert("x-delight-source", Value::from("iphone"));
    n.notify(
        t.app, replaces, "phone", t.summary, t.body, &actions, hints, -1,
    )
    .await
}
