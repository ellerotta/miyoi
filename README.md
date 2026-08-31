# miyoi

[![CI](https://github.com/ellerotta/miyoi/actions/workflows/ci.yml/badge.svg)](https://github.com/ellerotta/miyoi/actions/workflows/ci.yml)

`miyoi` is an independent, reverse-engineered macOS toolkit for configuring selected **attack shark** mice over their vendor HID interface

the Swift package provides the `MiyoiKit` library, the `miyoi` SwiftUI application executable, and the `miyoictl` command-line executable

this project is not affiliated with or endorsed by **attack shark**

## support

- macOS 15 or later
- Swift 6.3.2 or later
- R6: wired PID `0x0021`, wireless PID `0x0022`
- R5 Ultra: wired PID `0x0046`, wireless PID `0x0047`
- M5 Ultra: wired PID `0x0051`, wireless PID `0x0050`

only the vendor HID interface with vendor ID `0x373E` and usage page `0xFFFF` is used, other models, firmware versions, and bootloader modes are not supported

see [the protocol notes](docs/PROTOCOL.md) for the known wire format and [support guidance](docs/SUPPORT.md) before reporting a problem

## safety

changing device settings writes feature reports to the mouse or receiver

incorrect values or interrupted communication may leave settings in an unexpected state

firmware updates and bootloader operations are intentionally out of scope

use this software at your own risk

see [safety](docs/SAFETY.md) for details

## install

download the newest `Miyoi-*-macOS-universal.zip` from [releases](https://github.com/ellerotta/miyoi/releases), unzip it, and move `Miyoi.app` to `/Applications`

published builds are ad-hoc signed rather than notarized, so macOS quarantines them after download, clear the flag once with

```sh
xattr -dr com.apple.quarantine /Applications/Miyoi.app
```

the `miyoictl-*-macOS-universal.tar.gz` asset holds the command-line binary, and `SHA256SUMS.txt` covers both archives

## building

the package imports macOS IOKit and is not expected to build on Linux

unit tests cover hardware-independent public APIs and do not require a connected mouse

run `swift run miyoi-selftest` on minimal Command Line Tools installations

run `swift test` when the selected toolchain includes XCTest

see [building](docs/BUILDING.md) for release builds and testability notes

## CLI usage

most commands accept `--pid PID`; decimal and `0x`-prefixed hexadecimal values are supported

if omitted, `miyoictl` tries registered models in registry order

see [CLI usage](docs/CLI.md) before running commands that change device state

## license

licensed under the [MIT License](LICENSE).
