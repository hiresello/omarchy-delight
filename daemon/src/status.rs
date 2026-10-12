//! Status the CLI and Control Center read; rewritten only when it changes.

use crate::ams::NowPlaying;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Phone {
    pub name: String,
    pub address: String,
    pub connected: bool,
    pub paired: bool,
    pub notifications: bool,
    pub media: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub adapter: Option<String>,
    pub powered: bool,
    pub advertising: bool,
    pub pairing: bool,
    pub phones: Vec<Phone>,
    pub now_playing: Option<NowPlaying>,
    pub error: Option<String>,
}

pub fn runtime_dir() -> PathBuf {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    base.join("omarchy-delight")
}

pub fn socket_path() -> PathBuf {
    runtime_dir().join("delightd.sock")
}

pub struct Writer {
    path: PathBuf,
    last: Option<Status>,
}

impl Writer {
    pub fn new() -> Self {
        Self {
            path: runtime_dir().join("delightd.json"),
            last: None,
        }
    }

    pub fn write(&mut self, s: &Status) -> std::io::Result<()> {
        if self.last.as_ref() == Some(s) {
            return Ok(());
        }
        std::fs::create_dir_all(self.path.parent().unwrap())?;
        let tmp = self.path.with_extension("json.tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(s)?)?;
        std::fs::rename(&tmp, &self.path)?;
        self.last = Some(s.clone());
        Ok(())
    }
}
