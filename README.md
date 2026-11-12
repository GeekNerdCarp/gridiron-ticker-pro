# 🏈 Gridiron Ticker Pro

**Every NFL score, scrolling along the edge of your Mac, plus your fantasy team.**

A native, LED-style ticker for macOS that follows the whole NFL week: live scores, finals, kickoff times, odds and playoffs, with Mac notifications for your teams and a built-in fantasy tracker that scores your players live. Small, fast and private: no account, no ads, no tracking.

![Gridiron Ticker Pro showing a followed team's next game](docs/ticker.png)

## Why you'll like it

- **Always there, never in the way.** A slim bar along the top or bottom of any screen, with a menu-bar icon for everything else.
- **Built for football.** Records with ties, bye weeks, odds, close-game and upset badges, playoff rounds, overtime and the four quarters, not a generic scoreboard.
- **Your teams come first.** Follow a favorite and up to five more. Their games lead the ticker, get a ★, and can trigger notifications.
- **Fantasy built in.** Pick your players and watch your points update live, all on your Mac.
- **Native and light.** Written in Swift and AppKit. No Electron, no web view, no background services.

## The ticker

- **The whole NFL week.** Live scores with quarter and clock, today's finals, and upcoming games with kickoff time and TV channel. Team logos and records (ties included, like 5-2-1).
- **Spreads and over/unders** (optional). Turn on ESPN's betting line in Settings. Off by default.
- **Badges that matter.**
  - A red **CLOSE** badge for fourth-quarter and overtime games within one score and four minutes or less.
  - A red **UPSET ALERT** when a team favored by a touchdown or more (per ESPN's line) is trailing late.
  - A gold **MARQUEE** badge when two teams with strong records meet.
  - Live games with these badges move to the front.
- **Score-change flashes.** A glow when your team scores, on big moments, or on any score, your choice.
- **Bye weeks.** Followed teams on a bye get their own BYE WEEK entry.
- **Playoffs.** Wild Card through the Super Bowl, with round labels. Games whose teams aren't decided yet stay hidden until they are.
- **Next game.** A followed team without a game this week still shows its next one.
- **Filter by channel.** Show only games on the channels you have, such as FOX, CBS, NBC, ESPN or Prime Video. Your followed teams' games always come through.

## Your team

- **Follow your favorite, plus up to five more.** Their games scroll first, whether live, finished, or still to come.
- **Show only my team's game.** One game held still in the center, in your team's colors, refreshing every 10 seconds while it's live.
- **Menu-bar score.** Put your team's live score right in the menu bar.
- **Hide the bar until you need it.** It appears when your team is live or about to start.
- **Team alerts.** Mac notifications for:
  - kickoff,
  - every score, such as touchdown, field goal and safety,
  - halftime and overtime,
  - a close finish and the final result,
  - plus an optional reminder 15, 30 or 60 minutes before kickoff.
- **Spoiler-free mode.** Hide scores, tags and box scores (and the alerts that would give a result away) for your teams' games or for all games, so you can watch a recording safely.

## Fantasy team

Open **Fantasy Team…** from the menu-bar icon.

- **Build your roster.** Search every QB, RB, WR, TE and kicker in the league, plus each team's D/ST. Add an optional opponent for a matchup line.
- **ESPN standard scoring, live.** Passing, rushing and receiving yards and touchdowns, interceptions and lost fumbles, return touchdowns, kicker field goals by distance and extra points, and defense/special-teams scoring including points allowed and yards allowed. Points update as games happen.
- **Show it your way.** Put your players at the front of the ticker, at the end, or show only your fantasy team. Each player shows points, what they did, the game state, opponent, kickoff time and the line, with injury tags (OUT, DOUBTFUL, Q).
- **Matchup line.** `MY TEAM 84.2 – OPP 71.9, WINNING BY 12.3`.
- **Menu-bar total.** Your fantasy points, or the matchup score, right in the menu bar.
- **Fantasy alerts.** Touchdowns, a points milestone you choose (10 to 30) and players ruled out, doubtful or inactive.
- **Box-score integration.** Your players are listed with their points inside any game's popup.
- **Past weeks.** Each week's total is saved with your best week and your record against opponents.
- **Private.** Your roster stays on your Mac. It's not your ESPN league, and nothing is sent anywhere but ESPN's public data requests.

D/ST tiers are approximate (ESPN's own published tables vary), and two-point conversions aren't counted.

## Click for the details

Click any game for a box score popup:

- team stats side by side: total, passing and rushing yards, turnovers, first downs, third-down efficiency and time of possession,
- each team's top passer, rusher and receiver,
- the last play for live games,
- your fantasy players in that game,
- an **Open on ESPN** button. You can also set a click to open the ESPN page directly.

## Make it yours

- Top or bottom of the screen, on any display.
- Four text sizes, bar opacity from see-through to solid, three scroll speeds, pause when the pointer is over it.
- Team logos and records on or off, finals and upcoming games on or off.
- Use your team's colors for the bar in only-my-team mode.
- **Hide Ticker** for a menu-bar-only experience, **Refresh Now** any time, and open at login.

## Reliable and respectful

- **Handles ESPN's bad days.** If ESPN is unreachable, the ticker keeps showing your last good data and recovers on its own. If ESPN asks the app to slow down, it backs off, never more than four requests at once, and tells you in the menu.
- **Never hammers ESPN.** Live games refresh every 20 seconds, quiet times every couple of minutes, fantasy box scores every 30 seconds.
- **Private by design.** No account, no analytics, no ads. The app only talks to ESPN's public scoreboard and to GitHub for updates.
- **Self-updating.** Signed and notarized by Apple, with one-click updates through Sparkle.

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

Scores, schedules, teams, odds, box scores and player stats come from ESPN's public scoreboard API. That API isn't officially documented, so ESPN could change or remove it at any time, and the ticker may stop working until it's updated. Team logos are loaded from ESPN at runtime and are not bundled with the app.

**Can't reach ESPN?** If the ticker shows no games, check your internet connection first. If ESPN's servers are down or have changed their API, the ticker will recover on its own once they respond normally, or after an app update that handles the change.

## Disclaimer

Gridiron Ticker Pro is an independent project. It isn't affiliated with, endorsed by, or sponsored by the NFL, ESPN, or any team. All team names and logos are the property of their respective owners. Odds are shown for information only.

## License

[GPL-3.0](LICENSE). You're free to use, modify and share this code, and any version you distribute must stay open source under the same license.
