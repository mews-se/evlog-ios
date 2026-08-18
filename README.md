# EVLog

A native iPhone app for reading your own [TeslaMate](https://github.com/teslamate-org/teslamate)
data — drives, charges, statistics and battery health, in a SwiftUI interface built for the phone
rather than a dashboard squeezed onto a small screen.

EVLog talks only to servers you run yourself. It never connects to Tesla, and nothing leaves your
network.

## What it does

**Overview** — battery ring with range, lock state, location, temperatures, Sentry, degradation,
countries visited, software version and time since last contact.

**Drives** — grouped by day, each with a route map, a speed graph you can scrub, and efficiency as
a percentage of rated consumption. Drives where the battery heater ran are marked, since that is
often what explains a cold day's consumption.

**Charges** — session list separating AC from DC, with charge curves, added energy, cost and
average power. Costs TeslaMate does not have can be filled in from Tessie if you use it.

**Statistics** — week, month and year, drilling down from period to day to individual drives.
Charging statistics with top locations, AC/DC split and a weekday-by-hour heat map.

**Maps** — every track you have driven over a chosen period, and a range map showing how far the
current charge takes you, using a detour factor derived from your own trips rather than a guess.

## Requirements

- A running TeslaMate instance
- [teslamateapi](https://github.com/tobiasehlert/teslamateapi) reachable from your phone — this is
  the app's main data source
- Optionally Grafana, used for the visited-places map, battery health and a few queries the API
  does not expose
- Optionally a [Tessie](https://tessie.com) API key, only to fill in charging costs that TeslaMate
  never records

All four addresses are configured in Settings. The defaults point at a LAN address and will need
changing.

## Building

The Xcode project is generated, not committed:

```
brew install xcodegen
xcodegen generate
open EVLog.xcodeproj
```

Then pick your own team under Signing & Capabilities and run. A free Apple ID works — the app has
to be reinstalled from Xcode every seven days, which a paid Apple Developer Program membership
removes.

iOS 17 or later, iPhone only.

## A note on networking

The app allows plain HTTP so it can reach a server on your own LAN, which is the normal way to run
TeslaMate. If you expose your instance over HTTPS, or reach it through a VPN, nothing else needs
changing.

## Licence

MIT — see [LICENSE](LICENSE).

## Disclaimer

This project is an unofficial community tool and is not affiliated with, endorsed by, or supported
by the official TeslaMate project.
