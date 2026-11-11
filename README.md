# 🏈 Gridiron Ticker Pro

A scrolling, LED-style football score ticker for your Mac menu bar and desktop.

> **Status: early development.** This project is being built from a finished college-basketball ticker. The football data and features are arriving in phases, so it isn't ready to use yet. No releases have been published.

## Planned

- Live NFL scores, finals and upcoming kickoffs with team records and logos
- Follow your favorite teams, with alerts for kickoff, close games and finals
- Live game situation (down, distance, possession, red zone) in the ticker
- Click a game for a box score, plus bye-week and playoff handling
- Native Swift and AppKit, with no Electron, no account, no ads and no tracking
- One-click updates via Sparkle

## Build from source

Requires macOS 12 or newer and the Xcode command-line tools.

```bash
git clone https://github.com/GeekNerdCarp/gridiron-ticker-pro.git
cd gridiron-ticker-pro
./build.sh
open "dist/Gridiron Ticker Pro.app"
```

## Where the data comes from

Scores, schedules and teams come from ESPN's public scoreboard API. That API isn't officially documented, so ESPN could change or remove it at any time, and the ticker may stop working until it's updated. Team logos are loaded from ESPN at runtime and are not bundled with the app.

**Can't reach ESPN?** If the ticker shows no games, check your internet connection first. If ESPN's servers are down or have changed their API, the ticker will recover on its own once they respond normally, or after an app update that handles the change.

## Disclaimer

Gridiron Ticker Pro is an independent project. It isn't affiliated with, endorsed by, or sponsored by the NFL, ESPN, or any team. All team names and logos are the property of their respective owners.

## License

[GPL-3.0](LICENSE). You're free to use, modify and share this code, and any version you distribute must stay open source under the same license.
