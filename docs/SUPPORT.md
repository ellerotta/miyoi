# support

this is an independent community project. there is no official **attack shark** support or guaranteed compatibility with new firmware

## before reporting an issue

1. confirm the host is macOS 15 or later and record `swift --version`
2. run `swift build` and `swift test` from a clean checkout
3. run `swift run miyoictl list` and note the model, decimal/hex PID, product name, and usage page
4. for read failures, include the command and sanitized output
5. state whether the mouse is wired or wireless and include its firmware version when `info` can read it

do not include serial numbers or other device identifiers you consider sensitive

avoid repeated write attempts when the device is returning unexpected data

## scope

supported models and PIDs are listed in the [README](../README.md). requests involving unknown devices, firmware flashing, bootloader recovery, macro storage, Windows/Linux support, or hardware repair are outside the current project scope
