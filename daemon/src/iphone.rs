//! One connected iPhone: subscribe to ANCS and AMS on its GATT server and
//! mirror them onto the desktop.

use crate::ams::{self, NowPlaying};
use crate::ancs::{self, Action, Assembler, EventId, Response};
use crate::desktop::{self, NotificationsProxy, Toast};
use anyhow::{anyhow, Context, Result};
use bluer::gatt::remote::Characteristic;
use bluer::Device;
use futures::StreamExt;
use std::collections::HashMap;
use tokio::sync::{mpsc, watch};

pub enum Event {
    Media(NowPlaying),
    Capabilities { notifications: bool, media: bool },
}

pub struct Handles {
    pub media: Option<Characteristic>,
}

async fn find(device: &Device) -> Result<HashMap<uuid::Uuid, Characteristic>> {
    let mut out = HashMap::new();
    for svc in device.services().await? {
        let uuid = svc.uuid().await?;
        if uuid != ancs::SERVICE && uuid != ams::SERVICE {
            continue;
        }
        for ch in svc.characteristics().await? {
            out.insert(ch.uuid().await?, ch);
        }
    }
    Ok(out)
}

pub async fn attach(
    device: Device,
    notes: NotificationsProxy<'static>,
    events: mpsc::Sender<Event>,
    mut stop: watch::Receiver<bool>,
) -> Result<Handles> {
    let mut chars = find(&device).await?;
    let has_ancs = chars.contains_key(&ancs::NOTIFICATION_SOURCE);
    let has_ams = chars.contains_key(&ams::ENTITY_UPDATE);
    let _ = events
        .send(Event::Capabilities {
            notifications: has_ancs,
            media: has_ams,
        })
        .await;
    if !has_ancs && !has_ams {
        return Err(anyhow!(
            "no ANCS or AMS service; is this an iPhone, and is it paired?"
        ));
    }

    let media = chars.remove(&ams::REMOTE_COMMAND);
    if let Some(update) = chars.remove(&ams::ENTITY_UPDATE) {
        let mut stream = Box::pin(update.notify().await.context("subscribe AMS")?);
        for sub in ams::subscriptions() {
            update.write(&sub).await.context("AMS entity update")?;
        }
        let events = events.clone();
        let mut stop = stop.clone();
        tokio::spawn(async move {
            let mut now = NowPlaying::default();
            loop {
                tokio::select! {
                    _ = stop.changed() => break,
                    msg = stream.next() => match msg {
                        Some(b) => if now.apply(&b) { let _ = events.send(Event::Media(now.clone())).await; },
                        None => break,
                    }
                }
            }
        });
    }

    if let (Some(source), Some(data), Some(control)) = (
        chars.remove(&ancs::NOTIFICATION_SOURCE),
        chars.remove(&ancs::DATA_SOURCE),
        chars.remove(&ancs::CONTROL_POINT),
    ) {
        // Data Source must be subscribed before Notification Source.
        let mut data = Box::pin(data.notify().await.context("subscribe ANCS data")?);
        let mut source = Box::pin(source.notify().await.context("subscribe ANCS source")?);
        let mut actions = Box::pin(notes.receive_action_invoked().await?);
        tokio::spawn(async move {
            let mut asm = Assembler::default();
            let mut uid_to_toast: HashMap<u32, u32> = HashMap::new();
            let mut toast_to_uid: HashMap<u32, u32> = HashMap::new();
            let mut app_names: HashMap<String, String> = HashMap::new();
            let mut pending: HashMap<u32, ancs::SourceEvent> = HashMap::new();
            let mut waiting_app: HashMap<String, Vec<ancs::Attributes>> = HashMap::new();
            loop {
                tokio::select! {
                    _ = stop.changed() => break,
                    msg = source.next() => {
                        let Some(b) = msg else { break };
                        let Some(e) = ancs::parse_source(&b) else { continue };
                        match e.event {
                            EventId::Removed => {
                                pending.remove(&e.uid);
                                if let Some(id) = uid_to_toast.remove(&e.uid) {
                                    toast_to_uid.remove(&id);
                                    let _ = notes.close_notification(id).await;
                                }
                            }
                            // Don't replay the backlog that exists when we connect.
                            _ if e.flags.pre_existing() => {}
                            _ => {
                                pending.insert(e.uid, e);
                                let _ = control.write(&ancs::get_notification_attributes(e.uid)).await;
                            }
                        }
                    }
                    msg = data.next() => {
                        let Some(b) = msg else { break };
                        let ready: Vec<ancs::Attributes> = match asm.push(&b) {
                            Some(Response::Notification(a)) => {
                                let app_id = a.get(ancs::attr::APP_IDENTIFIER).unwrap_or("").to_owned();
                                if !app_id.is_empty() && !app_names.contains_key(&app_id) {
                                    let queue = waiting_app.entry(app_id.clone()).or_default();
                                    if queue.is_empty() {
                                        let _ = control.write(&ancs::get_app_attributes(&app_id)).await;
                                    }
                                    queue.push(a);
                                    continue;
                                }
                                vec![a]
                            }
                            Some(Response::App { app_id, display_name }) => {
                                let name = display_name.unwrap_or_else(|| app_id.clone());
                                app_names.insert(app_id.clone(), name);
                                waiting_app.remove(&app_id).unwrap_or_default()
                            }
                            None => continue,
                        };
                        for attrs in ready {
                        let app_id = attrs.get(ancs::attr::APP_IDENTIFIER).unwrap_or("").to_owned();
                        let Some(e) = pending.remove(&attrs.uid) else { continue };
                        let app = app_names.get(&app_id).map(String::as_str).unwrap_or("iPhone");
                        let title = attrs.get(ancs::attr::TITLE).unwrap_or(app);
                        let body = match (attrs.get(ancs::attr::SUBTITLE), attrs.get(ancs::attr::MESSAGE)) {
                            (Some(s), Some(m)) => format!("{s}\n{m}"),
                            (s, m) => s.or(m).unwrap_or("").to_owned(),
                        };
                        let toast = Toast {
                            app,
                            summary: title,
                            body: &body,
                            urgency: e.category.urgency(e.flags),
                            positive: e.flags.positive_action().then(|| attrs.get(ancs::attr::POSITIVE_ACTION_LABEL).unwrap_or("Accept")),
                            negative: e.flags.negative_action().then(|| attrs.get(ancs::attr::NEGATIVE_ACTION_LABEL).unwrap_or("Dismiss")),
                        };
                        let replaces = uid_to_toast.get(&attrs.uid).copied().unwrap_or(0);
                        if let Ok(id) = desktop::show(&notes, replaces, &toast).await {
                            uid_to_toast.insert(attrs.uid, id);
                            toast_to_uid.insert(id, attrs.uid);
                        }
                        }
                    }
                    sig = actions.next() => {
                        let Some(sig) = sig else { break };
                        let Ok(args) = sig.args() else { continue };
                        let Some(&uid) = toast_to_uid.get(&args.id) else { continue };
                        let action = if args.action_key == "positive" { Action::Positive } else { Action::Negative };
                        let _ = control.write(&ancs::perform_action(uid, action)).await;
                    }
                }
            }
            for id in uid_to_toast.into_values() {
                let _ = notes.close_notification(id).await;
            }
        });
    }

    Ok(Handles { media })
}
