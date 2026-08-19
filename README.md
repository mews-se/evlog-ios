# EVLog

A native iPhone client for your own [TeslaMate](https://github.com/teslamate-org/teslamate) server
— drives, charges, statistics and battery health, in an interface built for the phone rather than a
dashboard squeezed onto a small screen.

EVLog talks only to servers you run yourself. It never connects to Tesla, there is no account to
create, and nothing leaves your network.

> Version 1.0 is with Apple for review and is not on the App Store yet. Until it is, building it
> yourself is the way to run it — see [Building](#building).

[Privacy policy](https://mews-se.github.io/evlog-site/privacy/) ·
[Support](https://mews-se.github.io/evlog-site/support/)

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

## What's next

The [2.0 milestone](https://github.com/mews-se/evlog-ios/milestone/1) lists what the next release
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

All addresses are configured under Settings in the app.

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

iOS 17 or later, iPhone only.

## Licence

MIT — see [LICENSE](LICENSE).

## Disclaimer

This project is an unofficial community tool and is not affiliated with, endorsed by, or supported
by the official TeslaMate project.
