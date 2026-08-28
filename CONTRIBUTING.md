# Contributing

Thanks for looking. EVLog is a one-person hobby project, so here is what fits, how the project is
put together, and what will save us both some time.

## Scope

EVLog reads your own TeslaMate instance. It talks to teslamateapi, to Grafana for the few things
the API does not expose, and optionally to Tessie for the charging costs TeslaMate never receives
from Tesla. It does not talk to Tesla itself, and it never writes to your instance.

Anything that needs a Tesla login, sends data to a third party, or turns the app into a control
surface for the car is out of scope. Not because those are bad ideas — they are just a different
app.

## Building

```
brew install xcodegen
xcodegen generate
open EVLog.xcodeproj
```

The Xcode project is generated from `project.yml` and not committed, so run `xcodegen generate`
again after adding a file or editing that file. A new source file that is not in the generated
project does not fail loudly — it simply is not compiled.

iOS 18 or later, iPhone only.

## Before you open a pull request

Open an issue first for anything bigger than a fix. It saves you writing code that I then have to
turn down for reasons that were only in my head.

Branch from `dev` and open the pull request against it. `main` follows behind and is what the
outside sees: the front page, this file, and the source a release is cut from.

Look at the [open milestone](https://github.com/mews-se/evlog-ios/milestones) and the `planned`
label before you start. What is listed there is either being worked on already or decided, and it
is the cheapest way to avoid writing something twice. However, feel free to comment if you feel that
you want to work on something planned. Planned does not automatically mean me :)

Work lands in `dev` and waits there. Releases gather a body of changes rather than going out one at
a time, so a merged pull request can sit for a while before it reaches the App Store. That is the
plan, not neglect.

There is no test suite. The simulator is the test, so build and click through the screens your
change touches, including the ones that only differ when a value is missing — an empty Grafana
address, a charge without a cost, a drive shorter than a kilometre.

Keep commits focused. Subject in the imperative, and a body explaining why when the why is not
obvious from the diff.

## Strings

All user-facing text lives in `Sources/Localizable.xcstrings` and is English only. English doubles
as the key, but every key still carries an explicit `en` entry so the catalog and the compiler's
extraction stay in step. Plain `String(localized:)` does the job.

The app shipped with a Swedish translation up to 2.1 and dropped it in #38: keeping two languages
correct takes more time than one developer has. If you want to bring a language and keep its texts
alive over time, open an issue first.

Units follow the setting in the app, not the strings: TeslaMate's data is metric, and the imperial
mode converts at display time only.

Established terms stay put. Sentry is Sentry.

## Naming

TeslaMate is a trademark of the TeslaMate project. Mention it in prose and in compatibility
notices, spelled CamelCase, but keep it out of product and feature names.

## Licence

MIT. By contributing you agree that your work is published under it.
