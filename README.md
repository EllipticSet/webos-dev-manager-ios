# Dev Manager for webOS TV (iOS)

An iPhone companion app for LG webOS TVs in **Developer Mode** or with **root access**. Manage your TV from your iPhone over your local network.

Inspired by [Device/DevMode Manager for webOS TV](https://github.com/webosbrew/dev-manager-desktop) by the webOS Homebrew project.

## Features

- **Apps**: install, update and open apps, including from the [Homebrew catalog](https://repo.webosbrew.org)
- **Files**: browse, upload and download files on the TV
- **Terminal**: open an SSH terminal on your TV
- **Info**: check TV details and renew your Developer Mode session (or export a renewal script for cron)
- **Debug**: live logs, crash reports, PmLog levels and a Luna bus monitor
- **Certificates**: create SSH keys to sign in to rooted TVs without a password
- **App lock**: protect the app with Face ID or a passcode

## Requirements

- iPhone with iOS 26 or later
- An LG webOS TV on the same local network, with Developer Mode enabled or rooted (e.g. with Homebrew Channel)

## Building

The project was created with Bitrig. Open `Dev Manager.xcodeproj`, select your own team for signing, and run the `Dev Manager` scheme on a device or simulator. Unit tests live in the `Dev Manager Tests` target.

Swift Package dependencies are resolved automatically:

- [Citadel](https://github.com/orlandos-nl/Citadel) (MIT)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT)
- [Swift NIO SSH](https://github.com/apple/swift-nio-ssh) (Apache 2.0)

### Testing without a TV

`Tools/FakeTV/start.sh` starts a fake webOS TV on `127.0.0.1` (SSH on port 9922, Key Server on port 9991 with passphrase `A1B2C3`). It requires Python 3 and creates everything under `/tmp/faketv`. All keys it generates are throwaway.

The private keys in `Tests/TestKeys.swift` are test fixtures used only by the unit tests: they don't give access to any real device.

## Privacy

The app doesn't collect any data. Credentials stay in the iPhone's keychain and are used only to connect to your TVs. The only external services contacted are `repo.webosbrew.org` (Homebrew catalog) and `developer.lge.com` (Developer Mode status and renewal).

## Acknowledgments

This app is based on the ideas and workflows of [webosbrew/dev-manager-desktop](https://github.com/webosbrew/dev-manager-desktop), released under the Apache License 2.0. Many thanks to the webOS Homebrew community.

## Disclaimer

Dev Manager is an independent developer tool. It isn't affiliated with, sponsored by, or approved by LG Electronics or the webOS Homebrew project. webOS is a trademark of its respective owners. Use at your own risk.

## License

Released under the [Apache License 2.0](LICENSE).
