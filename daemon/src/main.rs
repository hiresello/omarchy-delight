//! delightd: Omarchy Delight's native iPhone link.
//!
//! The iPhone pairs with Omarchy over Bluetooth LE the way it pairs with a
//! watch or car: we advertise as a peripheral soliciting Apple's ANCS and
//! AMS services, the iPhone connects and bonds, and we then read its
//! notifications and control its media as a GATT client. No iPhone app.

mod ams;
mod ancs;
mod desktop;
mod iphone;
mod status;

use anyhow::{anyhow, Context, Result};
use bluer::adv::{Advertisement, AdvertisementHandle, Type};
use bluer::agent::{Agent, ReqError};
use bluer::{Adapter, AdapterEvent, Address, DeviceEvent, DeviceProperty};
use futures::StreamExt;
use std::collections::{BTreeSet, HashMap};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, watch};

const PAIRING_WINDOW: Duration = Duration::from_secs(120);

enum Msg {
    Phone(Address, iphone::Event),
    Attached(Address, iphone::Handles),
    Detached(Address),
    Device(Address),
    Command(String, tokio::sync::oneshot::Sender<String>),
    PairingDone,
}

fn usage() -> ! {
    eprintln!("usage: delightd [run | status | pair | media <play|pause|toggle|next|previous|volume-up|volume-down>]");
    std::process::exit(2)
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None | Some("run") => run().await,
        Some("status" | "pair" | "media") => client(&args.join(" ")).await,
        _ => usage(),
    }
}

async fn client(line: &str) -> Result<()> {
    let mut s = UnixStream::connect(status::socket_path())
        .await
        .context("delightd is not running")?;
    s.write_all(format!("{line}\n").as_bytes()).await?;
    let mut out = String::new();
    BufReader::new(s).read_line(&mut out).await?;
    print!("{out}");
    if out.starts_with("error") {
        std::process::exit(1);
    }
    Ok(())
}

async fn advertise(adapter: &Adapter, name: &str) -> Result<AdvertisementHandle> {
    let adv = Advertisement {
        advertisement_type: Type::Peripheral,
        solicit_uuids: BTreeSet::from([ancs::SERVICE, ams::SERVICE]),
        local_name: Some(name.to_owned()),
        discoverable: Some(true),
        // Generic computer.
        appearance: Some(0x0080),
        ..Default::default()
    };
    Ok(adapter.advertise(adv).await?)
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .map(|s| s.trim().to_owned())
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "Omarchy".into())
}

async fn run() -> Result<()> {
    let session = bluer::Session::new()
        .await
        .context("BlueZ is not available")?;
    let adapter = session
        .default_adapter()
        .await
        .context("no Bluetooth adapter")?;
    adapter.set_powered(true).await.ok();
    let mut writer = status::Writer::new();
    let mut st = status::Status {
        adapter: Some(adapter.name().to_owned()),
        ..Default::default()
    };
    st.powered = adapter.is_powered().await.unwrap_or(false);

    // Pairing: only confirm passkeys while the user has opened the pairing window.
    let pairing = Arc::new(AtomicBool::new(false));
    let p = pairing.clone();
    let _agent = session
        .register_agent(Agent {
            request_default: true,
            request_confirmation: Some(Box::new(move |_req| {
                let ok = p.load(Ordering::SeqCst);
                Box::pin(async move {
                    if ok {
                        Ok(())
                    } else {
                        Err(ReqError::Rejected)
                    }
                })
            })),
            ..Default::default()
        })
        .await
        .context("register pairing agent")?;

    let name = hostname();
    let _adv = match advertise(&adapter, &name).await {
        Ok(h) => {
            st.advertising = true;
            Some(h)
        }
        Err(e) => {
            st.error = Some(format!("cannot advertise: {e}"));
            None
        }
    };
    writer.write(&st).ok();

    let conn = zbus::Connection::session()
        .await
        .context("no session bus")?;
    let notes = desktop::NotificationsProxy::new(&conn).await?;
    let (tx, mut rx) = mpsc::channel::<Msg>(64);

    // Device discovery: watch every known and newly added device.
    {
        let tx = tx.clone();
        let mut evs = Box::pin(adapter.events().await?);
        for addr in adapter.device_addresses().await? {
            tx.send(Msg::Device(addr)).await.ok();
        }
        tokio::spawn(async move {
            while let Some(e) = evs.next().await {
                if let AdapterEvent::DeviceAdded(addr) = e {
                    if tx.send(Msg::Device(addr)).await.is_err() {
                        break;
                    }
                }
            }
        });
    }

    // Control socket for the delight CLI.
    {
        let path = status::socket_path();
        std::fs::create_dir_all(path.parent().unwrap()).ok();
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path).context("bind control socket")?;
        let tx = tx.clone();
        tokio::spawn(async move {
            while let Ok((s, _)) = listener.accept().await {
                let tx = tx.clone();
                tokio::spawn(async move {
                    let (r, mut w) = s.into_split();
                    let mut line = String::new();
                    if BufReader::new(r).read_line(&mut line).await.is_ok() {
                        let (otx, orx) = tokio::sync::oneshot::channel();
                        if tx
                            .send(Msg::Command(line.trim().to_owned(), otx))
                            .await
                            .is_ok()
                        {
                            if let Ok(reply) = orx.await {
                                let _ = w.write_all(format!("{reply}\n").as_bytes()).await;
                            }
                        }
                    }
                });
            }
        });
    }

    let mut watched: HashMap<Address, watch::Sender<bool>> = HashMap::new();
    let mut media: HashMap<Address, bluer::gatt::remote::Characteristic> = HashMap::new();
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;

    loop {
        let msg = tokio::select! {
            m = rx.recv() => match m { Some(m) => m, None => break },
            _ = sigterm.recv() => break,
            _ = tokio::signal::ctrl_c() => break,
        };
        match msg {
            Msg::Device(addr) => {
                if watched.contains_key(&addr) {
                    continue;
                }
                let device = adapter.device(addr)?;
                let (stop_tx, stop_rx) = watch::channel(false);
                watched.insert(addr, stop_tx);
                tokio::spawn(watch_device(device, notes.clone(), tx.clone(), stop_rx));
            }
            Msg::Attached(addr, h) => {
                if let Some(c) = h.media {
                    media.insert(addr, c);
                }
                refresh_phones(&adapter, &mut st, &watched).await;
            }
            Msg::Detached(addr) => {
                media.remove(&addr);
                if let Some(p) = st.phones.iter_mut().find(|p| p.address == addr.to_string()) {
                    p.connected = false;
                }
                if media.is_empty() {
                    st.now_playing = None;
                }
            }
            Msg::Phone(
                addr,
                iphone::Event::Capabilities {
                    notifications,
                    media: m,
                },
            ) => {
                refresh_phones(&adapter, &mut st, &watched).await;
                if let Some(p) = st.phones.iter_mut().find(|p| p.address == addr.to_string()) {
                    p.notifications = notifications;
                    p.media = m;
                }
            }
            Msg::Phone(_, iphone::Event::Media(n)) => st.now_playing = Some(n),
            Msg::PairingDone => {
                pairing.store(false, Ordering::SeqCst);
                st.pairing = false;
            }
            Msg::Command(line, reply) => {
                let r = command(&line, &adapter, &pairing, &mut st, &media, &tx).await;
                let _ = reply.send(match r {
                    Ok(s) => s,
                    Err(e) => format!("error: {e}"),
                });
            }
        }
        st.powered = adapter.is_powered().await.unwrap_or(false);
        writer.write(&st).ok();
    }

    for (_, stop) in watched {
        let _ = stop.send(true);
    }
    let _ = std::fs::remove_file(status::socket_path());
    let _ = std::fs::remove_file(status::runtime_dir().join("delightd.json"));
    Ok(())
}

async fn command(
    line: &str,
    adapter: &Adapter,
    pairing: &Arc<AtomicBool>,
    st: &mut status::Status,
    media: &HashMap<Address, bluer::gatt::remote::Characteristic>,
    tx: &mpsc::Sender<Msg>,
) -> Result<String> {
    let mut words = line.split_whitespace();
    match words.next() {
        Some("status") => Ok(serde_json::to_string(st)?),
        Some("pair") => {
            adapter.set_discoverable(true).await.ok();
            adapter.set_pairable(true).await.ok();
            pairing.store(true, Ordering::SeqCst);
            st.pairing = true;
            let tx = tx.clone();
            tokio::spawn(async move {
                tokio::time::sleep(PAIRING_WINDOW).await;
                let _ = tx.send(Msg::PairingDone).await;
            });
            Ok(format!("pairing for {}s", PAIRING_WINDOW.as_secs()))
        }
        Some("media") => {
            let cmd = words
                .next()
                .and_then(ams::Command::parse)
                .ok_or_else(|| anyhow!("unknown media command"))?;
            let ch = media
                .values()
                .next()
                .ok_or_else(|| anyhow!("no iPhone with media control connected"))?;
            ch.write(&[cmd as u8]).await?;
            Ok("ok".into())
        }
        _ => Err(anyhow!("unknown command")),
    }
}

async fn refresh_phones(
    adapter: &Adapter,
    st: &mut status::Status,
    watched: &HashMap<Address, watch::Sender<bool>>,
) {
    for addr in watched.keys() {
        let Ok(d) = adapter.device(*addr) else {
            continue;
        };
        let connected = d.is_connected().await.unwrap_or(false);
        let paired = d.is_paired().await.unwrap_or(false);
        if !paired {
            continue;
        }
        let name = d.alias().await.unwrap_or_else(|_| addr.to_string());
        let address = addr.to_string();
        match st.phones.iter_mut().find(|p| p.address == address) {
            Some(p) => {
                p.name = name;
                p.connected = connected;
                p.paired = paired;
            }
            None => st.phones.push(status::Phone {
                name,
                address,
                connected,
                paired,
                ..Default::default()
            }),
        }
    }
}

async fn watch_device(
    device: bluer::Device,
    notes: desktop::NotificationsProxy<'static>,
    tx: mpsc::Sender<Msg>,
    stop: watch::Receiver<bool>,
) {
    let addr = device.address();
    let Ok(evs) = device.events().await else {
        return;
    };
    let mut evs = Box::pin(evs);
    let mut session: Option<watch::Sender<bool>> = None;
    let mut ready = device.is_services_resolved().await.unwrap_or(false);
    loop {
        if ready && session.is_none() {
            let (stx, srx) = watch::channel(false);
            let (etx, mut erx) = mpsc::channel(16);
            match iphone::attach(device.clone(), notes.clone(), etx, srx).await {
                Ok(h) => {
                    session = Some(stx);
                    let _ = tx.send(Msg::Attached(addr, h)).await;
                    let tx2 = tx.clone();
                    tokio::spawn(async move {
                        while let Some(e) = erx.recv().await {
                            if tx2.send(Msg::Phone(addr, e)).await.is_err() {
                                break;
                            }
                        }
                    });
                }
                Err(_) => {
                    // Not an iPhone (or not yet bonded); retry on the next resolve.
                }
            }
        }
        let mut stop = stop.clone();
        tokio::select! {
            _ = stop.changed() => break,
            e = evs.next() => match e {
                Some(DeviceEvent::PropertyChanged(DeviceProperty::ServicesResolved(r))) => {
                    ready = r;
                    if !r {
                        if let Some(s) = session.take() { let _ = s.send(true); }
                        let _ = tx.send(Msg::Detached(addr)).await;
                    }
                }
                Some(DeviceEvent::PropertyChanged(DeviceProperty::Connected(false))) => {
                    ready = false;
                    if let Some(s) = session.take() { let _ = s.send(true); }
                    let _ = tx.send(Msg::Detached(addr)).await;
                }
                Some(_) => {}
                None => break,
            }
        }
    }
    if let Some(s) = session.take() {
        let _ = s.send(true);
    }
}
