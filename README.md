# <img src="assets/icon-180.png" alt="" width="40"> EVLog

![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-F05138?logo=swift&logoColor=white)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A native iPhone client for your own [TeslaMate](https://github.com/teslamate-org/teslamate) server
— drives, charges, statistics and battery health, in an interface built for the phone rather than a
dashboard squeezed onto a small screen.

EVLog talks only to servers you run yourself. It never connects to Tesla, there is no account to
create, and nothing leaves your network.

[Download it on the App Store](https://apps.apple.com/app/evlog/id6802532911) — free, iOS 18 or
later. Every version that reaches the App Store gets a
[tag and a release](https://github.com/mews-se/evlog-ios/releases) here. `main` holds the build
most recently sent to Apple — normally the one in the store, marked by the latest tag — while new
work gathers on `dev`. To build what is in the store, start from the latest tag; for how, see
[Building](#building).

[Privacy policy](https://mews-se.github.io/evlog-site/privacy/) ·
[Support](https://mews-se.github.io/evlog-site/support/)

## What it does

**Overview** — battery ring with range, what the cable is doing right now, TeslaMate's own status
glyphs for preconditioning, open doors and windows, tyre pressure and more, lock state, location,
temperatures, Sentry, degradation, countries visited, software version and time since last contact.
The car's name opens a spec sheet: model, VIN, efficiency, and with a Tessie key the car's own
configuration. From here you reach a map of every place the car has been over any period you
choose, on a plain map or satellite imagery, and a range map showing how far the current charge
takes you, using a detour factor derived from your own trips rather than a guess.

**Timeline** — drives, charges and the parking in between, as one flow per day, going back as far
as you choose: the last week, the last month, this year or everything. A parked row says how long
the car stood and what it cost the battery, and a short stop gets one too if it cost anything. When
the odometer shows the car moved while nothing was logged, the row says so instead of pretending the
car stood still. Swipe left and right inside a drive or a charge to step through the day without
going back to the list.

**Drives** — a route map, a speed graph you can drag along to follow the car, energy and regen,
consumption, and efficiency as a percentage of rated consumption. Drives where the battery heater
ran are marked, since that is often what explains a cold day's consumption.

**Charges** — AC and DC told apart, the charging curve with a readout under your finger, added
and used energy, average and peak power, cost, and what the battery heater and cabin climate drew
while the car charged. A car left plugged in across several charging processes is shown as one
charge. Costs TeslaMate does not have can be filled in from Tessie if you use it.

**Statistics** — week, month and year, drilling down from period to day to individual drives.
Charging statistics with top locations that open into the charges behind them, AC/DC split and a
weekday-by-hour heat map. Destinations: where the car goes most often and where it covers the most
distance, each opening into the drives behind it, weekdays against weekends, and a heat map of when
you drive. Temperature and consumption: consumption grouped by outside temperature, with the
coldest fifth of the driving set against the warmest.

**Demo mode** — with no server configured the app starts in three weeks of built-in example data,
so every screen above can be tried before anything is set up. A switch in Settings takes you back
there any time, and the title says DEMO MODE whenever the data is canned.

## What's next

The [open milestone](https://github.com/mews-se/evlog-ios/milestones) lists what the next release
is meant to carry, and the [planned](https://github.com/mews-se/evlog-ios/labels/planned) label
marks the ideas that are agreed rather than merely filed. Releases gather a body of work instead of
trickling out one change at a time, so most of what is happening is in the branches rather than in
the release list.

## What you need

- A running TeslaMate instance
- [teslamateapi](https://github.com/tobiasehlert/teslamateapi) reachable from your phone — this is
  the app's main data source
- Optionally Grafana, used for the visited-places map, battery health and a few queries the API
  does not expose
- Optionally a [Tessie](https://tessie.com) API key, only to fill in charging costs that TeslaMate
  never records

All addresses are configured under Settings in the app. Until a server address is in place the app
runs in demo mode, so there is something to look at before there is anything to connect to.

The app allows plain HTTP to your own network: private addresses such as 192.168.x.x and 10.x.x.x,
`.local` names, and hostnames without a dot. That covers a LAN and a VPN alike. A server you reach
by a public domain name needs HTTPS, which needs no other change in the app.

## Adding teslamateapi

TeslaMate has no HTTP API of its own, so EVLog reads through
[teslamateapi](https://github.com/tobiasehlert/teslamateapi). If you are not running it yet, put a
`docker-compose.override.yml` next to your existing TeslaMate compose file and leave the original
untouched:

```yaml
services:
  teslamateapi:
    image: tobiasehlert/teslamateapi:latest
    restart: always
    depends_on:
      - database
      - mosquitto
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=the same password as your database service
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - TZ=Europe/Stockholm
      - ENABLE_COMMANDS=false
    ports:
      - 8080:8080
```

Then `docker compose up -d`, and point the app at `http://your-server:8080`. `ENABLE_COMMANDS=false`
keeps the API read-only, which is all EVLog needs — it never writes to your instance.

Grafana needs nothing extra. TeslaMate's own compose file already runs it with
`GF_AUTH_ANONYMOUS_ENABLED=true`, and that is the access EVLog uses for the visited-places map and
battery health.

## Building

The Xcode project is generated rather than committed, so a fresh clone has no `.xcodeproj` until
you run:

```
brew install xcodegen
xcodegen generate
```

iOS 18 or later, iPhone only.

That is enough to build and run it in the simulator. To put it on your own iPhone, change
`DEVELOPMENT_TEAM` in `project.yml` first — the identifier in the file is mine, and Xcode will not
sign for a team you are not a member of. A free Apple ID works: pick Personal Team when Xcode asks.
Apps signed that way stop launching after seven days and have to be run from Xcode again to renew.

## Licence

MIT — see [LICENSE](LICENSE).

## Disclaimer

This project is an unofficial community tool and is not affiliated with, endorsed by, or supported
by the official TeslaMate project.
