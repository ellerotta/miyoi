# building

## requirements

- macOS 15 or later
- Xcode Command Line Tools with Swift 6.3.2 or later for builds and self-tests
- full Xcode for the XCTest suite

the package links against IOKit through `MiyoiKit`, so macOS is the supported build host

## Development

run these commands from the repository root:

```sh
swift build
swift run miyoi-selftest
swift run miyoictl list
```

with full Xcode selected using `xcode-select`, also run `swift test`

create an optimized CLI binary with:

```sh
swift build -c release --product miyoictl
```

Swift Package Manager places the binary under `.build/release/miyoictl`

## tests

the unit suite exercises public, deterministic behavior including the device registry, key-code names, binding encoding and descriptions, RGB formatting, value semantics, and public errors. It does not enumerate or open HID devices

request-frame construction and response parsing are not independently testable through the current public API: frame construction is module-internal, while response parsing is private to `MiyoiDevice` and depends on a concrete `HIDTransport`

adding direct coverage would require a production-code seam such as an injectable transport and extracted parser, which is outside the current documentation-and-test-only scope
