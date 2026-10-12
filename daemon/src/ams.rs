//! Apple Media Service (AMS) wire format, per Apple's published AMS
//! specification: control and observe what's playing on the iPhone.

use serde::Serialize;
use uuid::{uuid, Uuid};

pub const SERVICE: Uuid = uuid!("89d3502b-0f36-433a-8ef4-c502ad55f8dc");
pub const REMOTE_COMMAND: Uuid = uuid!("9b3c81d8-57b1-4a8a-b8df-0e56f7ca51c2");
pub const ENTITY_UPDATE: Uuid = uuid!("2f7cabce-808d-411f-9a0c-bb92ba96c102");

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Play = 0,
    Pause = 1,
    TogglePlayPause = 2,
    NextTrack = 3,
    PreviousTrack = 4,
    VolumeUp = 5,
    VolumeDown = 6,
}

impl Command {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "play" => Self::Play,
            "pause" => Self::Pause,
            "toggle" | "play-pause" => Self::TogglePlayPause,
            "next" => Self::NextTrack,
            "previous" | "prev" => Self::PreviousTrack,
            "volume-up" => Self::VolumeUp,
            "volume-down" => Self::VolumeDown,
            _ => return None,
        })
    }
}

const ENTITY_PLAYER: u8 = 0;
const ENTITY_TRACK: u8 = 2;

const PLAYER_NAME: u8 = 0;
const PLAYER_PLAYBACK_INFO: u8 = 1;
const PLAYER_VOLUME: u8 = 2;
const TRACK_ARTIST: u8 = 0;
const TRACK_ALBUM: u8 = 1;
const TRACK_TITLE: u8 = 2;
const TRACK_DURATION: u8 = 3;

/// Entity Update subscriptions, one write each.
pub fn subscriptions() -> [Vec<u8>; 2] {
    [
        vec![
            ENTITY_PLAYER,
            PLAYER_NAME,
            PLAYER_PLAYBACK_INFO,
            PLAYER_VOLUME,
        ],
        vec![
            ENTITY_TRACK,
            TRACK_ARTIST,
            TRACK_ALBUM,
            TRACK_TITLE,
            TRACK_DURATION,
        ],
    ]
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NowPlaying {
    pub player: Option<String>,
    pub playing: bool,
    pub elapsed: Option<f64>,
    pub volume: Option<f64>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub title: Option<String>,
    pub duration: Option<f64>,
}

fn non_empty(s: &str) -> Option<String> {
    (!s.is_empty()).then(|| s.to_owned())
}

impl NowPlaying {
    /// Apply one Entity Update notification. Returns false if it was malformed.
    pub fn apply(&mut self, b: &[u8]) -> bool {
        if b.len() < 3 {
            return false;
        }
        let value = String::from_utf8_lossy(&b[3..]);
        match (b[0], b[1]) {
            (ENTITY_PLAYER, PLAYER_NAME) => self.player = non_empty(&value),
            (ENTITY_PLAYER, PLAYER_PLAYBACK_INFO) => {
                // "PlaybackState,PlaybackRate,ElapsedTime"; state 1 = playing.
                let mut parts = value.split(',');
                self.playing = parts.next().map(str::trim) == Some("1");
                parts.next();
                self.elapsed = parts.next().and_then(|s| s.trim().parse().ok());
            }
            (ENTITY_PLAYER, PLAYER_VOLUME) => self.volume = value.trim().parse().ok(),
            (ENTITY_TRACK, TRACK_ARTIST) => self.artist = non_empty(&value),
            (ENTITY_TRACK, TRACK_ALBUM) => self.album = non_empty(&value),
            (ENTITY_TRACK, TRACK_TITLE) => self.title = non_empty(&value),
            (ENTITY_TRACK, TRACK_DURATION) => self.duration = value.trim().parse().ok(),
            _ => {}
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn update(entity: u8, attr: u8, v: &str) -> Vec<u8> {
        let mut b = vec![entity, attr, 0];
        b.extend_from_slice(v.as_bytes());
        b
    }

    #[test]
    fn tracks_now_playing() {
        let mut n = NowPlaying::default();
        assert!(n.apply(&update(0, 0, "Music")));
        assert!(n.apply(&update(0, 1, "1,1.0,12.5")));
        assert!(n.apply(&update(2, 2, "Midnight City")));
        assert!(n.apply(&update(2, 0, "M83")));
        assert!(n.apply(&update(2, 3, "243.9")));
        assert_eq!(n.player.as_deref(), Some("Music"));
        assert!(n.playing);
        assert_eq!(n.elapsed, Some(12.5));
        assert_eq!(n.title.as_deref(), Some("Midnight City"));
        assert_eq!(n.duration, Some(243.9));
        assert!(n.apply(&update(0, 1, "0,0.0,13.0")));
        assert!(!n.playing);
        assert!(!n.apply(&[0, 1]));
    }

    #[test]
    fn parses_commands() {
        assert_eq!(Command::parse("toggle"), Some(Command::TogglePlayPause));
        assert_eq!(Command::parse("next").map(|c| c as u8), Some(3));
        assert_eq!(Command::parse("eject"), None);
        assert_eq!(subscriptions()[1], vec![2, 0, 1, 2, 3]);
    }
}
