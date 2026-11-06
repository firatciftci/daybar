<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/icon-dark.png">
    <img src=".github/assets/icon-light.png" width="128" height="128" alt="Daybar app icon">
  </picture>
</p>

<h1 align="center">Daybar</h1>

<p align="center">Your calendar in the menu bar, one click away.</p>

<p align="center">
  <a href="https://github.com/firatciftci/daybar/releases/latest">Download</a> ·
  <a href="https://github.com/firatciftci/daybar/actions/workflows/ci.yml"><img src="https://github.com/firatciftci/daybar/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
</p>

Daybar puts today's date in your menu bar. Click it to see your month, week, or day, check what's next, and add an event by typing it the way you'd say it. It reads and writes the same calendars and reminders as the Calendar and Reminders apps, so there's no account to set up and nothing to sync.

## Features

- Four views. Switch between a month grid, a week strip, a day timeline, and an Up next list that shows what's happening now and your free time around it.
- Quick add in plain words. Type "Coffee with Ana Friday 9am at Blue Bottle /work" and Daybar fills in the time, place, and calendar.
- Join calls from the menu bar. When a Zoom, Teams, Meet, Webex, or FaceTime call is about to start, an icon appears next to the date. Click it to join.
- Edit without leaving the panel. Create, edit, duplicate, and delete events, including repeating ones, with the calendar still in view.
- Reminders alongside events. Overdue and upcoming reminders sit in the list, and you can check them off there.
- Weather for each day. Daily forecasts from Apple Weather, for your current location or a city you choose.
- Birthdays and attendees. Contact names and photos for birthdays and the people invited to an event.
- Calendar sets. Group calendars into sets like Work and Home, then switch between them.
- Search. Find events by title, place, notes, or calendar, with matching days marked in the grid.

## Requirements

macOS 27 or later.

## Install

1. Download `Daybar.dmg` from the [latest release](https://github.com/firatciftci/daybar/releases/latest).
2. Open it and drag Daybar to your Applications folder.
3. Open Daybar and allow access to your calendars when macOS asks.

Each release is signed with a Developer ID and notarized by Apple.

## Quick add

Type into the field at the bottom of the panel and press Return.

| You type | Daybar adds |
| --- | --- |
| `Lunch with Sam tomorrow at noon` | An event tomorrow from 12 to 1 PM |
| `Standup every Monday 9:30am for 15m /work` | A weekly 15-minute event in your Work calendar |
| `Dentist Nov 14 3pm at Main St Dental alert 1h` | An event with a location and an alert an hour before |
| `Flight to Istanbul Dec 20` | An all-day event |
| `remind me to call the bank Friday` | A reminder due Friday |

Start with `remind`, `todo`, or `task` to add a reminder. Add `/name` to pick a calendar or list by the start of its name.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>K</kbd> | Show or hide Daybar from anywhere (you can change this in Settings) |
| <kbd>⌘</kbd><kbd>1</kbd> to <kbd>⌘</kbd><kbd>4</kbd> | Switch between Month, Week, Day, and Up next |
| <kbd>⌘</kbd><kbd>T</kbd> | Go to today |
| <kbd>⌘</kbd><kbd>N</kbd> | New event |
| <kbd>⌘</kbd><kbd>F</kbd> | Search |
| <kbd>⌘</kbd><kbd>E</kbd> | Edit the open event |
| <kbd>⌘</kbd><kbd>↩</kbd> | Save the event you're editing, or join the open event's call |
| <kbd>⌘</kbd><kbd>⌫</kbd> | Delete the open event |
| <kbd>⌘</kbd><kbd>[</kbd> | Go back |
| <kbd>Tab</kbd> and <kbd>⇧</kbd><kbd>Tab</kbd> | Move between fields while editing |
| <kbd>Esc</kbd> | Leave a field, close search, or close the panel |

## Privacy

Daybar has no accounts, analytics, or servers of its own. Your events, reminders, and contacts stay on your Mac and are read through Apple's frameworks. The only network requests are for weather: Daybar sends your approximate location, or the city you chose, to Apple Weather, and to [Open-Meteo](https://open-meteo.com) if Apple Weather is unavailable. Turn off weather in Settings and Daybar makes no network requests at all.

## Build from source

You need Xcode 27 and [Homebrew](https://brew.sh).

```sh
git clone https://github.com/firatciftci/daybar.git
cd daybar
brew bundle
xcodegen generate
open Daybar.xcodeproj
```

The Xcode project is generated from `project.yml`, so edit that file instead of the project settings, and run `xcodegen generate` again after changing it. To build without a signing team, pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`. Weather needs a signed build with the WeatherKit capability.

Before you open a pull request, run the same checks CI does:

```sh
tools/check.sh
```

It formats the code with swift-format, lints it with SwiftLint, builds with warnings treated as errors, and runs SwiftLint's analyzer on the build. See [CONTRIBUTING.md](CONTRIBUTING.md) for more.

## License

[MIT](LICENSE)
