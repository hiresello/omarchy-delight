# Continuity Camera

Use an Android phone or iPhone as a webcam. It appears to every app (Chromium,
OBS, meeting apps) as a camera named **Continuity Camera**.

```bash
delight camera install && delight camera enable
delight camera connect --wifi <phone-ip>   # or --usb
delight camera disconnect
```

Install the free **DroidCam** app on the phone. Over Wi-Fi, entering the
phone's IP (`delight camera set ip <IP>`) is the reliable way to connect;
automatic discovery is best-effort. Over USB, enable USB debugging (Android)
or trust the computer (iPhone).

Until a phone is connected the tile says **Connect your phone**
(`needs-setup`). Your other cameras keep working: only the Continuity Camera
device is added and removed. Iriun is supported as an opt-in backend.

Details: [modules/camera/README.md](../../modules/camera/README.md).
