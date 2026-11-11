# Read-only evidence for the UX3607OA IR illuminator.
# Does not change a device, write a register, or turn an LED on.
# Run from an elevated PowerShell if DriverStore listings come back empty:
#   powershell -NoProfile -ExecutionPolicy Bypass -File collect-windows.ps1

param(
    [string]$Out = (Join-Path $env:USERPROFILE "a16-ir-evidence-windows")
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Save-Text($Name, $Text) {
    $path = Join-Path $Out $Name
    $Text | Out-File -FilePath $path -Encoding utf8
    Write-Host "wrote $path"
}

function Try-Run($Name, [scriptblock]$Block) {
    try {
        $text = & $Block | Out-String
        if (-not $text) { $text = "(no output)" }
        Save-Text $Name $text
    } catch {
        Save-Text $Name ("failed: " + $_.Exception.Message)
    }
}

Save-Text "README.txt" @"
Read-only Windows bundle. This script did not enable a camera or an LED.
Do not commit this directory. Interpretation: docs/a16-ir-illuminator.md

Start with:
  computer.txt          model
  pnp-camera.txt        camera devices and instance ids
  driver-files.txt      qccam / HM1092 / AeoB filenames
  string-hits.txt       FLASH, STROBE, LED, TLMM, PPP_RESOURCE hits
  acpi.txt              only if acpidump.exe was on PATH
"@

Try-Run "computer.txt" {
    Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemFamily
    Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion
    Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" |
        Select-Object SystemManufacturer, SystemProductName, BaseBoardProduct, BIOSVersion
}

Try-Run "pnp-camera.txt" {
    Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue |
        Format-List Status, Class, FriendlyName, InstanceId
    Write-Output "---- other Qualcomm camera-ish devices ----"
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InstanceId -match 'QCOM|HIMX|OVTI|CAM' -or
            $_.FriendlyName -match 'camera|infrared|IR |HM1092|OV02'
        } |
        Format-List Status, Class, FriendlyName, InstanceId
}

Try-Run "pnp-drivers.txt" {
    pnputil /enum-devices /class Camera
    Write-Output "---- driver packages whose original name matches the camera stack ----"
    pnputil /enum-drivers | Select-String -Pattern 'qccam|hm1092|ov02|camera' -Context 3,3
}

$store = Join-Path $env:SystemRoot "System32\DriverStore\FileRepository"
$fileList = New-Object System.Collections.Generic.List[string]
if (Test-Path $store) {
    Get-ChildItem $store -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'qccam|hm1092|ov02|camera|aeob|sensormodule' } |
        ForEach-Object {
            Get-ChildItem $_.FullName -File -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { $fileList.Add($_.FullName) }
        }
}
Save-Text "driver-files.txt" (($fileList | Sort-Object) -join "`r`n")

function Get-HitLines([string]$Path) {
    $pattern = 'FLASH|STROBE|ILLUM|IR_LED|IRLED|LM364|AW364|PM8550|pmh0101|PM8010|PPP_RESOURCE|TLMMGPIO|flash-led|led-sources|CAMI_RES|CAMF_RES'
    $hits = New-Object System.Collections.Generic.List[string]
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    } catch {
        try { $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read') } catch { return $hits }
    }
    try {
        $len = [int][Math]::Min($fs.Length, 8MB)
        $buf = New-Object byte[] $len
        [void]$fs.Read($buf, 0, $len)
    } finally {
        $fs.Close()
    }
    $text = [System.Text.Encoding]::ASCII.GetString($buf)
    $text = [regex]::Replace($text, '[^\x20-\x7E]+', "`n")
    foreach ($line in ($text -split "`n")) {
        if ($line.Length -ge 6 -and $line -match $pattern) {
            $hits.Add($line)
            if ($hits.Count -ge 80) { break }
        }
    }
    return $hits
}

$hitText = New-Object System.Text.StringBuilder
foreach ($f in ($fileList | Sort-Object)) {
    $item = Get-Item $f -ErrorAction SilentlyContinue
    if (-not $item) { continue }
    if ($item.Length -gt 8MB) {
        [void]$hitText.AppendLine("skip (>8MB, copy it and run collect.sh --blobs): $f")
        continue
    }
    $hits = Get-HitLines $f
    if ($hits.Count -gt 0) {
        [void]$hitText.AppendLine("==== $f")
        foreach ($h in $hits) { [void]$hitText.AppendLine($h) }
        [void]$hitText.AppendLine()
    }
}
if ($hitText.Length -eq 0) {
    $hitText.AppendLine("no hits. If driver-files.txt is empty, re-run elevated.")
}
Save-Text "string-hits.txt" $hitText.ToString()

$acpidump = Get-Command acpidump.exe -ErrorAction SilentlyContinue
if ($acpidump) {
    $acpiDir = Join-Path $Out "acpi"
    New-Item -ItemType Directory -Force -Path $acpiDir | Out-Null
    & acpidump.exe -b -z $acpiDir | Out-File (Join-Path $Out "acpi.txt") -Encoding utf8
    Write-Host "wrote ACPI tables under $acpiDir"
} else {
    Save-Text "acpi.txt" @"
acpidump.exe is not on PATH.
Install ACPICA (acpidump and iasl), then run: acpidump -b
and: iasl -d dsdt.dat
Linux can dump the same tables from /sys/firmware/acpi/tables when that directory exists.
"@
}

Write-Host "bundle: $Out"
Write-Host "Do not commit it."
