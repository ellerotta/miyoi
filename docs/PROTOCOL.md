# miyoi — reverse-engineered attack shark HID protocol

native macOS support for **attack shark** mices (vendor **0x373E**)
sources: official web driver bundle `index-e3a67185.js` (WebHID) at `https://www.xvalleyinno.top/AttackShark/`, config `Config/env-models.json`, verified live against an R5 Ultra via IOKit on macOS.

## supported devices (all "new protocol", IsNewProtocol=1)

| model    | wired PID | wireless 8K PID | mouse bootloader | dongle bootloader |
|----------|-----------|-----------------|------------------|-------------------|
| R6       | 0x0021    | 0x0022          | 0xB021           | 0xB022            |
| R5 Ultra | 0x0046    | 0x0047          | 0xB046           | 0xB047            |
| M5 Ultra | 0x0051    | 0x0050          | 0xB051           | 0xB050            |

VID is always `0x373E`. a physical mouse exposes **3 HID interfaces**:
- `usagePage=0xFFFF` — **vendor / config interface** (this is the one to use)
- `usagePage=0x0001` — mouse
- `usagePage=0x000C` — consumer

no input monitoring / accessibility permission required on macOS because we talk to the vendor interface via feature reports

## transport

64-byte **feature report**, report ID **0**.

- write request: `IOHIDDeviceSetReport(kIOHIDReportTypeFeature, id: 0, data)`
- read response: `IOHIDDeviceGetReport(kIOHIDReportTypeFeature, id: 0, &data)`
- delay ~100–150 ms between write and read (`commonDelay`).

## request frame (64 bytes)

| byte | meaning |
|------|---------|
| 0–1  | 0x00    |
| 2    | device address (2 = mouse, 0 = dongle) |
| 3    | payload length in bytes `[6..6+len)`. Example: set DPI stages → 26 (2 header + 24 data) |
| 4    | target device: 1 = mouse settings, 2 = LED/DPI indicator, 3 = buttons, 4 = macro, 5 = LCD |
| 5    | command, READ = WRITE | 0x80 |
| 6..  | payload (device id, value, data …) |

## response frame (64 bytes)

layout differs per device firmware family — host detects it from the firmware version command ("hidIndex" in the JS):

- layout "old-layout" (`hidIndex` used as offset): marker `0xA1` at `[0]`, command echo at `[5]`, data starts at `[6]`.
- layout "new-layout": marker `0xA1` at `[1]`, command echo at `[6]`, data starts at `[7]`.

detection (see `getFirmwareVersion` in JS): if firmware response has echo at `[6]` -> new layout, else echo at `[5]` -> old layout. R5 Ultra answered old-layout.

common accepted frames also return marker `0x02`.

## commands (new protocol)

WRITE / READ pair -> `(target[4], cmd)`.

| Feature                | target | WRITE cmd | READ cmd | payload (write)           | response data                                 |
|------------------------|--------|-----------|----------|---------------------------|-----------------------------------------------|
| Polling rate           | 1      | 0x00      | 0x80     | [tgt=1, value]            | value at data[2]                              |
| DPI stages info        | 1      | 0x01      | 0x81     | [tgt, 6]                  | count, then 4B/stage (DPI hi|lo, color hi|lo) |
| Active DPI / stage num | 1      | 0x02      | 0x82     | [tgt, index]              | stage index                                   |
| Angle snap             | 1      | 0x04      | 0x84     | [tgt, 0/1]                | 0/1                                           |
| LOD                    | 1      | 0x08      | 0x88     | [tgt, val]                | value                                         |
| Debounce               | 0      | 0x08      | 0x88     | [tgt, val]                | value                                         |
| Motion sync            | 1      | 0x09      | 0x89     | [tgt, 0/1]                | 0/1                                           |
| Ripple control         | 1      | 0x0A      | 0x8A     | [tgt, 0/1]                | 0/1                                           |
| Hyper mode             | 1      | 0x0B      | 0x8B     | [tgt, 0/1]                | 0/1                                           |
| DPIXY on/off           | 1      | 0x0D      | 0x8D     | [tgt, 0/1]                | 0/1                                           |
| Tracking mode          | 1      | 0x13      | 0x93     | [tgt, 0/1]                | 0/1                                           |
| Sleep time             | 0      | 0x07      | 0x87     | [tgt, hi, lo]             | (hi<<8)+lo                                    |
| DPI indicator          | 2      | 0x04      | 0x84     | [tgt, 0/1]                | 0/1                                           |
| Battery                | 0      | —         | 0x83     | —                         | percent                                       |
| Profile ID             | 0      | 0x05      | 0x85     | [index]                   | index                                         |
| Profile list           | 0      | —         | 0x86     | —                         | bitmask                                       |
| DPI max                | 1      | —         | 0x8C     | —                         | 16-bit BE                                     |
| Sensor model           | 1      | —         | 0x8F     | —                         | value                                         |
| Firmware               | 0      | —         | 0x81     | 16                        | 4 bytes "a.b.c.d"                             |
| EID                    | 0      | —         | 0x80     | —                         | value                                         |
| Reset profile          | 0      | 0x0D      | —        | [tgt]                     | —                                             |
| auto default           | —      | special   | —        | 0x05?                     |                                               |
| Button combine         | 3      | 0x01      | 0x81     | [tgt, 0/1]                | 0/1                                           |
| Button map             | 3      | 0x00      | 0x80     | see section               | see section                                   |
| Macro alloc            | 4      | 0x01      | —        | id u16 BE …               | —                                             |
| Delete macro           | 4      | 0x02      | —        | [idHi, idLo]              | —                                             |
| Light effect           | 2      | 0x00      | 0x80     | [tgt, mode, …4B, data...] | mode                                          |
| Lightness              | 2      | 0x02      | 0x82     | [tgt, mode, val]          | value                                         |

## response examples captured on R5 Ultra

```
firmware  A1 00 02 06 00 81 00 00 0C 00 00  → 0.12.0.0
battery   A1 00 02 02 00 83 00 60           → 96 %
polling   A1 00 02 02 01 80 01 80 00        → value at data[?]
active    A1 00 02 02 01 82 01 03 00        → stage 3
dpiMax    A1 00 02 02 01 8C 75 30           → 30000
stages    A1 00 02 0E 01 81 01 03 04 B0 04 B0 09 60 09 60 0C 80 0C 80
          → count=3, stages 1200, 2400, 3200 (X==Y; color field duplicates Y)
profile   A1 00 02 01 00 85 01              → profile 1
sleep     A1 00 02 03 00 87 01 FF FF         → 65535 (off)
```

## notes / gotchas

- battery percent is the second data byte (old layout: `data[7]`)
- polling byte semantics differ per model; see mappings agent (Hz table) - value `0x01` maps to 1000 Hz on R5 Ultra
- firmware updates (bootloader `0xB0x`, `program`/`verify` flow) are complex; out of scope for v1
- macro storage and command details have not been documented or validated and are out of scope for the currently supported protocol surface
