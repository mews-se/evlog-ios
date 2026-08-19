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

iOS 17 or later, iPhone only.

## Before you open a pull request

Open an issue first for anything bigger than a fix. It saves you writing code that I then have to
turn down for reasons that were only in my head.

Branch from `dev` and open the pull request against it. `main` is what has shipped, and it only
moves when a release does.

Look at the [open milestone](https://github.com/mews-se/evlog-ios/milestones) and the `planned`
label before you start. What is listed there is either being worked on already or decided, and it
is the cheapest way to avoid writing something twice.

Work lands in `dev` and waits there. Releases gather a body of changes rather than going out one at
a time, so a merged pull request can sit for a while before it reaches the App Store. That is the
plan, not neglect.

There is no test suite. The simulator is the test, so build and click through the screens your
change touches, including the ones that only differ when a value is missing — an empty Grafana
address, a charge without a cost, a drive shorter than a kilometre.

Keep commits focused. Subject in the imperative, and a body explaining why when the why is not
obvious from the diff.

## Strings

All user-facing text lives in `Sources/Localizable.xcstrings` with both `en` and `sv`. English is
the source language and doubles as the key, but every key still needs an explicit `en` entry:
without one there is no English bundle to switch to, and the in-app language picker silently stays
in Swedish.

Use `String(localized:, bundle: .current)` rather than plain `String(localized:)`. The language
picker works by pointing `Bundle.main` at the chosen `.lproj`, and only the `bundle:` form goes
through the lookup that respects it.

Established terms stay put. Sentry is Sentry. Where TeslaMate already has Swedish wording for
something, that wording is the reference.

## Naming

TeslaMate is a trademark of the TeslaMate project. Mention it in prose and in compatibility
notices, spelled CamelCase, but keep it out of product and feature names.

## Licence

MIT. By contributing you agree that your work is published under it.
