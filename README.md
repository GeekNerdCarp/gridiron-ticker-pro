# 🏈 Gridiron Ticker Pro

A scrolling, LED-style NFL score ticker for your Mac.

![Gridiron Ticker Pro showing a followed team's next game](docs/ticker.png)

## Features

- **Every game of the week.** Live scores, finals and upcoming kickoffs, with team records (ties included) and logos. Bye-week teams are noted.
- **Follow your favorite team, and more.** Their games scroll first and get a ★. **Show only my team's game** holds one game still in the center in your team's colors.
- **Team alerts.** Mac notifications for kickoff, every score (touchdown, field goal and so on), halftime, overtime, a close finish and the final, plus a reminder before kickoff.
- **Optional betting odds.** Turn on the spread and over/under in Settings. Off by default.
- **Badges.** A red **CLOSE** badge for late one-score games, **UPSET ALERT** when a big favorite is trailing, and a gold **MARQUEE** badge when two strong teams meet.
- **Click for a box score.** Team stats, top passer, rusher and receiver, the last play for live games, and a button to open the game on ESPN.
- **Fantasy team.** Pick your QBs, RBs, WRs, TEs, kickers and D/ST, plus an optional opponent, under **Fantasy Team…** in the menu. Live points use ESPN standard scoring, with a matchup line, a menu-bar total, alerts for touchdowns, point milestones and injuries, and a history of past weeks. Your roster stays on your Mac.
- **Filter by channel.** Show only games on the channels you have. Your followed teams always come through.
- **Playoffs.** Wild Card through the Super Bowl, with round labels.
- **Spoiler-free mode.** Hide scores (and the alerts that would give them away) for games you're recording.
- **Menu-bar score and your choice of display.** Put your team's live score in the menu bar, pick text size, opacity, scroll speed, top or bottom of the screen, any monitor, and open at login.
- **Small and native.** Written in Swift with AppKit. No Electron, no account, no ads, no tracking.

## Install

1. Download **Gridiron-Ticker-Pro.dmg** from the [latest release](../../releases/latest). It's signed and notarized by Apple, so it opens without a security warning.
2. Open it and drag **Gridiron Ticker Pro** into **Applications**.
3. Launch it. The ticker appears along the bottom of your screen and a football appears in the menu bar. Click it for the menu and settings.

Requires macOS 12 or newer. Works on Apple Silicon and Intel.

## Updates

Gridiron Ticker Pro updates itself. It checks this repository's latest GitHub release shortly after it launches and once a day, and when there's a newer version it offers to install it. You can also choose **Check for Updates…** in the menu.

## Build from source

Requires the Xcode command-line tools.

```bash
git clone https://github.com/GeekNerdCarp/gridiron-ticker-pro.git
cd gridiron-ticker-pro
./build.sh
open "dist/Gridiron Ticker Pro.app"
```

## Where the data comes from

Scores, schedules, teams and odds come from ESPN's public scoreboard API. That API isn't officially documented, so ESPN could change or remove it at any time, and the ticker may stop working until it's updated. Team logos are loaded from ESPN at runtime and are not bundled with the app. The ticker refreshes every 20 seconds while games are live and every 2 minutes otherwise.

**Can't reach ESPN?** If the ticker shows no games, check your internet connection first. If ESPN's servers are down or have changed their API, the ticker will recover on its own once they respond normally, or after an app update that handles the change.

## Disclaimer

Gridiron Ticker Pro is an independent project. It isn't affiliated with, endorsed by, or sponsored by the NFL, ESPN, or any team. All team names and logos are the property of their respective owners.

## License

[GPL-3.0](LICENSE). You're free to use, modify and share this code, and any version you distribute must stay open source under the same license.
