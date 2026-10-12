//! Apple Notification Center Service (ANCS) wire format, per Apple's published
//! ANCS specification. The iPhone is the GATT server; we are the client.

use uuid::{uuid, Uuid};

pub const SERVICE: Uuid = uuid!("7905f431-b5ce-4e99-a40f-4b1e122d00d0");
pub const NOTIFICATION_SOURCE: Uuid = uuid!("9fbf120d-6301-42d9-8c58-25e699a21dbd");
pub const CONTROL_POINT: Uuid = uuid!("69d1d8f3-45e1-49a8-9821-9bbdfdaad9d9");
pub const DATA_SOURCE: Uuid = uuid!("22eac6e9-24d6-4bb5-be44-b36ace7c7bfb");

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventId {
    Added,
    Modified,
    Removed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EventFlags(pub u8);

impl EventFlags {
    pub fn silent(self) -> bool {
        self.0 & 0x01 != 0
    }
    pub fn important(self) -> bool {
        self.0 & 0x02 != 0
    }
    pub fn pre_existing(self) -> bool {
        self.0 & 0x04 != 0
    }
    pub fn positive_action(self) -> bool {
        self.0 & 0x08 != 0
    }
    pub fn negative_action(self) -> bool {
        self.0 & 0x10 != 0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Category {
    Other,
    IncomingCall,
    MissedCall,
    Voicemail,
    Social,
    Schedule,
    Email,
    News,
    HealthAndFitness,
    BusinessAndFinance,
    Location,
    Entertainment,
    Unknown(u8),
}

impl Category {
    fn from_u8(v: u8) -> Self {
        use Category::*;
        match v {
            0 => Other,
            1 => IncomingCall,
            2 => MissedCall,
            3 => Voicemail,
            4 => Social,
            5 => Schedule,
            6 => Email,
            7 => News,
            8 => HealthAndFitness,
            9 => BusinessAndFinance,
            10 => Location,
            11 => Entertainment,
            n => Unknown(n),
        }
    }

    /// freedesktop notification urgency: 0 low, 1 normal, 2 critical.
    pub fn urgency(self, flags: EventFlags) -> u8 {
        match self {
            Category::IncomingCall => 2,
            _ if flags.important() => 2,
            _ if flags.silent() => 0,
            _ => 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceEvent {
    pub event: EventId,
    pub flags: EventFlags,
    pub category: Category,
    pub category_count: u8,
    pub uid: u32,
}

/// Parse an 8-byte Notification Source notification.
pub fn parse_source(b: &[u8]) -> Option<SourceEvent> {
    if b.len() < 8 {
        return None;
    }
    let event = match b[0] {
        0 => EventId::Added,
        1 => EventId::Modified,
        2 => EventId::Removed,
        _ => return None,
    };
    Some(SourceEvent {
        event,
        flags: EventFlags(b[1]),
        category: Category::from_u8(b[2]),
        category_count: b[3],
        uid: u32::from_le_bytes([b[4], b[5], b[6], b[7]]),
    })
}

pub mod attr {
    pub const APP_IDENTIFIER: u8 = 0;
    pub const TITLE: u8 = 1;
    pub const SUBTITLE: u8 = 2;
    pub const MESSAGE: u8 = 3;
    pub const POSITIVE_ACTION_LABEL: u8 = 6;
    pub const NEGATIVE_ACTION_LABEL: u8 = 7;
    pub const APP_DISPLAY_NAME: u8 = 0;
}

const CMD_GET_NOTIFICATION_ATTRIBUTES: u8 = 0;
const CMD_GET_APP_ATTRIBUTES: u8 = 1;
const CMD_PERFORM_NOTIFICATION_ACTION: u8 = 2;

const MAX_TITLE: u16 = 64;
const MAX_MESSAGE: u16 = 512;

/// The attributes we request for every notification, in request order.
pub const REQUESTED: [u8; 6] = [
    attr::APP_IDENTIFIER,
    attr::TITLE,
    attr::SUBTITLE,
    attr::MESSAGE,
    attr::POSITIVE_ACTION_LABEL,
    attr::NEGATIVE_ACTION_LABEL,
];

pub fn get_notification_attributes(uid: u32) -> Vec<u8> {
    let mut v = vec![CMD_GET_NOTIFICATION_ATTRIBUTES];
    v.extend_from_slice(&uid.to_le_bytes());
    for id in REQUESTED {
        v.push(id);
        match id {
            attr::TITLE | attr::SUBTITLE => v.extend_from_slice(&MAX_TITLE.to_le_bytes()),
            attr::MESSAGE => v.extend_from_slice(&MAX_MESSAGE.to_le_bytes()),
            _ => {}
        }
    }
    v
}

pub fn get_app_attributes(app_id: &str) -> Vec<u8> {
    let mut v = vec![CMD_GET_APP_ATTRIBUTES];
    v.extend_from_slice(app_id.as_bytes());
    v.push(0);
    v.push(attr::APP_DISPLAY_NAME);
    v
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Positive = 0,
    Negative = 1,
}

pub fn perform_action(uid: u32, action: Action) -> Vec<u8> {
    let mut v = vec![CMD_PERFORM_NOTIFICATION_ACTION];
    v.extend_from_slice(&uid.to_le_bytes());
    v.push(action as u8);
    v
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Attributes {
    pub uid: u32,
    pub values: Vec<(u8, String)>,
}

impl Attributes {
    pub fn get(&self, id: u8) -> Option<&str> {
        self.values
            .iter()
            .find(|(k, _)| *k == id)
            .map(|(_, v)| v.as_str())
            .filter(|v| !v.is_empty())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    Notification(Attributes),
    App {
        app_id: String,
        display_name: Option<String>,
    },
}

/// Reassembles Data Source responses, which the iPhone may split across
/// several GATT notifications. Responses arrive in request order, so the
/// assembler is told what it is waiting for.
#[derive(Debug, Default)]
pub struct Assembler {
    buf: Vec<u8>,
}

impl Assembler {
    pub fn push(&mut self, chunk: &[u8]) -> Option<Response> {
        self.buf.extend_from_slice(chunk);
        let (resp, used) = parse_response(&self.buf)?;
        self.buf.drain(..used);
        Some(resp)
    }
}

fn read_tuples(b: &[u8], mut at: usize, count: usize) -> Option<(Vec<(u8, String)>, usize)> {
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        if b.len() < at + 3 {
            return None;
        }
        let id = b[at];
        let len = u16::from_le_bytes([b[at + 1], b[at + 2]]) as usize;
        at += 3;
        if b.len() < at + len {
            return None;
        }
        out.push((id, String::from_utf8_lossy(&b[at..at + len]).into_owned()));
        at += len;
    }
    Some((out, at))
}

fn parse_response(b: &[u8]) -> Option<(Response, usize)> {
    match *b.first()? {
        CMD_GET_NOTIFICATION_ATTRIBUTES => {
            if b.len() < 5 {
                return None;
            }
            let uid = u32::from_le_bytes([b[1], b[2], b[3], b[4]]);
            let (values, used) = read_tuples(b, 5, REQUESTED.len())?;
            Some((Response::Notification(Attributes { uid, values }), used))
        }
        CMD_GET_APP_ATTRIBUTES => {
            let nul = b[1..].iter().position(|&c| c == 0)? + 1;
            let app_id = String::from_utf8_lossy(&b[1..nul]).into_owned();
            let (values, used) = read_tuples(b, nul + 1, 1)?;
            let display_name = values
                .into_iter()
                .next()
                .map(|(_, v)| v)
                .filter(|v| !v.is_empty());
            Some((
                Response::App {
                    app_id,
                    display_name,
                },
                used,
            ))
        }
        _ => Some((Response::Notification(Attributes::default()), b.len())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tuple(id: u8, s: &str) -> Vec<u8> {
        let mut v = vec![id];
        v.extend_from_slice(&(s.len() as u16).to_le_bytes());
        v.extend_from_slice(s.as_bytes());
        v
    }

    #[test]
    fn parses_notification_source() {
        let e = parse_source(&[0, 0x18, 4, 2, 0x2a, 0, 0, 0]).unwrap();
        assert_eq!(e.event, EventId::Added);
        assert_eq!(e.category, Category::Social);
        assert_eq!(e.uid, 42);
        assert!(e.flags.positive_action() && e.flags.negative_action());
        assert!(!e.flags.silent());
        assert!(parse_source(&[0, 0, 0]).is_none());
        assert!(parse_source(&[9, 0, 0, 0, 0, 0, 0, 0]).is_none());
    }

    #[test]
    fn incoming_calls_are_critical() {
        assert_eq!(Category::IncomingCall.urgency(EventFlags(0)), 2);
        assert_eq!(Category::Social.urgency(EventFlags(1)), 0);
        assert_eq!(Category::Email.urgency(EventFlags(0)), 1);
    }

    #[test]
    fn encodes_commands() {
        assert_eq!(
            get_notification_attributes(0x0102_0304),
            vec![0, 4, 3, 2, 1, 0, 1, 64, 0, 2, 64, 0, 3, 0, 2, 6, 7]
        );
        assert_eq!(get_app_attributes("com.a"), b"\x01com.a\x00\x00".to_vec());
        assert_eq!(perform_action(7, Action::Negative), vec![2, 7, 0, 0, 0, 1]);
    }

    fn notification_response(uid: u32) -> Vec<u8> {
        let mut v = vec![0];
        v.extend_from_slice(&uid.to_le_bytes());
        for (id, s) in [
            (0, "net.whatsapp.WhatsApp"),
            (1, "Ana"),
            (2, ""),
            (3, "Dinner at 8?"),
            (6, "Reply"),
            (7, "Clear"),
        ] {
            v.extend(tuple(id, s));
        }
        v
    }

    #[test]
    fn reassembles_fragmented_responses() {
        let full = notification_response(9);
        let mut a = Assembler::default();
        let mut got = None;
        for chunk in full.chunks(7) {
            got = a.push(chunk);
        }
        let Some(Response::Notification(n)) = got else {
            panic!("no response")
        };
        assert_eq!(n.uid, 9);
        assert_eq!(n.get(attr::TITLE), Some("Ana"));
        assert_eq!(n.get(attr::SUBTITLE), None);
        assert_eq!(n.get(attr::MESSAGE), Some("Dinner at 8?"));
        assert_eq!(n.get(attr::NEGATIVE_ACTION_LABEL), Some("Clear"));
    }

    #[test]
    fn partial_response_waits() {
        let full = notification_response(1);
        let mut a = Assembler::default();
        assert!(a.push(&full[..full.len() - 1]).is_none());
        assert!(a.push(&full[full.len() - 1..]).is_some());
    }

    #[test]
    fn parses_app_attributes() {
        let mut v = b"\x01com.apple.MobileSMS\x00".to_vec();
        v.extend(tuple(0, "Messages"));
        let mut a = Assembler::default();
        assert_eq!(
            a.push(&v),
            Some(Response::App {
                app_id: "com.apple.MobileSMS".into(),
                display_name: Some("Messages".into())
            })
        );
    }
}
