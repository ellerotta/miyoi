# CLI usage

examples below use `swift run miyoictl`

for an optimized build, substitute `.build/release/miyoictl`

## device selection

commands accept an optional `--pid PID` or `--pid=PID`

both decimal and `0x`-prefixed hexadecimal values are supported

```sh
swift run miyoictl info --pid 0x0047
swift run miyoictl battery --pid=71
```

without `--pid`, the CLI selects the first connected supported model in registry order

## r/o commands

```sh
swift run miyoictl list
swift run miyoictl info [--pid PID]
swift run miyoictl battery [--pid PID]
swift run miyoictl poll [--pid PID]
swift run miyoictl dpi [--pid PID]
swift run miyoictl dpi-active [--pid PID]
swift run miyoictl lod [--pid PID]
swift run miyoictl bind [--pid PID] list
```

## commands that change settings

```sh
swift run miyoictl poll [--pid PID] 1000
swift run miyoictl dpi-set [--pid PID] 800:800,1600:1600,3200:3200
swift run miyoictl dpi-active [--pid PID] 1
swift run miyoictl lod [--pid PID] 1.0
```

button indices are model-specific

run `bind list` first; the currently supported models expose indices 1 through 5

```sh
swift run miyoictl bind [--pid PID] set 1 off
swift run miyoictl bind [--pid PID] set 1 key W
swift run miyoictl bind [--pid PID] set 1 key 4
swift run miyoictl bind [--pid PID] set 1 dpi 1600
swift run miyoictl bind [--pid PID] set 1 macro 1
```

the `key` value can be a recognized key name or a decimal/hexadecimal HID usage code

the CLI validates input, reports failures on stderr with a nonzero exit code, and reads modified settings back before printing `ok`
