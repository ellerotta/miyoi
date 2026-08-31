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

## app bundle

`build-app.sh` builds the `miyoi` product, assembles `Miyoi.app` with the Swift Package Manager resource bundle, and signs the result ad-hoc

it reads three optional environment variables:

- `MIYOI_VERSION` sets `CFBundleShortVersionString`, default `1.0`
- `MIYOI_BUILD` sets `CFBundleVersion`, default `1000`
- `MIYOI_ARCHS` is a space-separated architecture list, for example `arm64 x86_64` for a universal binary

the macOS 27 SDK declares SwiftUI's `@State` and friends as macros implemented by the `SwiftUIMacros` plugin, which ships only with full Xcode. when the selected toolchain has no `libSwiftUIMacros.dylib`, the script falls back to the newest installed SDK that predates those macros, which keeps Command Line Tools-only installs building. set `SDKROOT` to override the choice

## continuous integration

`.github/workflows/ci.yml` builds every product, runs `swift test` and the self-test harness, and assembles the app bundle on each push and pull request

`.github/workflows/release.yml` runs on `v*` tags. it repeats the test suite, builds universal binaries, and publishes `Miyoi-<version>-macOS-universal.zip`, `miyoictl-<version>-macOS-universal.tar.gz`, and `SHA256SUMS.txt` to a GitHub release. the version comes from the tag, so `v1.2.3` produces version `1.2.3`, and a tag with a prerelease suffix such as `v1.2.3-beta.1` is published as a prerelease

re-running a release for an existing tag replaces its assets rather than failing, and the same workflow can be started manually with a tag input

## tests

the unit suite exercises public, deterministic behavior including the device registry, key-code names, binding encoding and descriptions, RGB formatting, value semantics, and public errors. It does not enumerate or open HID devices

request-frame construction and response parsing are not independently testable through the current public API: frame construction is module-internal, while response parsing is private to `MiyoiDevice` and depends on a concrete `HIDTransport`

adding direct coverage would require a production-code seam such as an injectable transport and extracted parser, which is outside the current documentation-and-test-only scope
