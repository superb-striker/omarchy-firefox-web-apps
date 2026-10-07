# Omarchy Web Apps Through Firefox

Use Firefox for Omarchy web apps without installing Chromium.

When Firefox is the default browser, Omarchy's `omarchy-launch-webapp` passes Chromium's `--app=URL` option to a Chromium fallback. 
If Chromium is absent, the desktop reports an error such as:

```text
Path "--app=https:/omarchy.org/manual" does not exist!
```

This script installs a user-local launcher that uses Firefox's native **Taskbar Tabs** instead. 
The resulting window has its own application identity and hides the normal tab strip. 
Non-Firefox browsers continue through Omarchy's original launcher.

## Related Omarchy issues and pull requests

This project is a local solution for [omacom/omarchy#7034][issue-7034], where web-app launches fail when Firefox is the default browser and Chromium is not installed.
Omarchy falls back to a missing `chromium.desktop`, leaving `uwsm-app` to interpret `--app=<url>` as an executable path.

Several upstream pull requests address the same area, but they make different tradeoffs. Their status as of October 7, 2026 is:

| Link | Status | Relationship to this project |
| --- | --- | --- |
| [Issue #7034: launch webapp fails when default browser is Firefox][issue-7034] | Open | Tracks the exact failure reproduced above. |
| [PR #7039: Support Firefox as a web app browser][pr-7039] | Open, currently conflicting | Adds Firefox to Omarchy's Chromium-style `--app` path. This project instead uses Firefox's native `-taskbar-tab` interface. |
| [PR #9206: Warn clearly when no Chromium browser can launch a web app][pr-9206] | Open, currently conflicting | Finds another installed Chromium-family browser or reports a useful error. It does not provide Firefox web-app windows. |
| [PR #11044: Allow web apps to open in the default browser][pr-11044] | Open | Adds an `xdg-open` choice for a normal tab or browser window. It preserves Firefox cookies and extensions, but it does not hide normal browser chrome. |
| [PR #13879: Launch web apps in an installed Chromium-based browser][pr-13879] | Open | Ports the Chromium fallback and clear-error approach to Omarchy's current launcher. Chromium remains required for an app-style window. |
| [PR #9172: Fall back to an installed Chromium-family browser][pr-9172] | Closed without merging | Earlier version of the installed-Chromium fallback now represented by newer proposals. |
| [Issue #9197: No warning when all Chromium-family browsers are removed][issue-9197] | Closed | Tracks the related opaque failure when no supported Chromium browser exists. |

None of the pending approaches currently integrates Firefox Taskbar Tabs into `omarchy-launch-webapp`. 
This repository fills that gap locally without modifying `/usr/share/omarchy` and can be removed if Omarchy gains equivalent native Firefox support.

## Requirements

- Omarchy with the Lua Hyprland configuration
- Firefox with Taskbar Tabs support
- `jq`, `xdg-utils`, `uwsm`, and GNU core utilities
- Firefox set as the default web browser

Taskbar Tabs are currently experimental on Linux and guarded by the `browser.taskbarTabs.enabled` preference. 
Mozilla documents the component in its [Firefox source documentation][taskbar-tabs].

## Install

Run the installer from this repository:

```bash
./install.sh
```

The installer:

1. Installs `~/.local/bin/omarchy-launch-webapp`.
2. Places `~/.local/bin` before Omarchy's system commands for desktop actions.
3. Enables `browser.taskbarTabs.enabled` in the active Firefox profile.
4. Reloads Hyprland and checks for configuration errors.
5. Stores backups under `~/.local/state/omarchy-firefox-web-apps/backups`.

Restart Firefox after installation. Firefox reads `user.js` only during startup. 
You can then use **Ctrl+Space → Learn → Omarchy** normally.

## Verify

Open the Omarchy manual from the menu. Its window should have no regular tab
strip or address bar. Firefox creates the registration on first launch:

```text
~/.config/mozilla/firefox/<profile>/taskbartabs/taskbartabs.json
~/.local/share/applications/firefox.webapp-<id>.desktop
```

The launcher reads that registry on later launches and supplies Firefox's
permanent app ID.

Firefox currently opens a new Taskbar Tab window each time the launcher runs.
That behavior comes from Firefox's Taskbar Tabs command-line handler.

## Uninstall

Run:

```bash
./uninstall.sh
```

The uninstaller removes only blocks managed by `omarchy-firefox-web-apps` and restores the
launcher that existed before installation when one was backed up. Restart
Firefox afterward.

Firefox's generated Taskbar Tab registration and icon are intentionally left
in place. Firefox owns those files, and removing them would also discard the
installed web-app record. They can be removed through Firefox when its web-app
management interface is available.

## How it works

Firefox accepts the following native command-line form:

```text
firefox -taskbar-tab <id> -new-window <url> -profile <path> -container 0
```

The local launcher resolves Firefox's active profile, finds an existing app ID
by hostname, and calls Firefox through `uwsm-app`. On the first launch it sends
a provisional UUID; Firefox creates the permanent registration and desktop
entry. The launcher delegates unchanged to `/usr/share/omarchy/bin/omarchy-launch-webapp`
when Firefox is not the default browser.

No file under `/usr/share/omarchy` is modified.

[taskbar-tabs]: https://firefox-source-docs.mozilla.org/browser/components/taskbartabs/docs/index.html
[issue-7034]: https://github.com/omacom/omarchy/issues/7034
[issue-9197]: https://github.com/omacom/omarchy/issues/9197
[pr-7039]: https://github.com/omacom/omarchy/pull/7039
[pr-9172]: https://github.com/omacom/omarchy/pull/9172
[pr-9206]: https://github.com/omacom/omarchy/pull/9206
[pr-11044]: https://github.com/omacom/omarchy/pull/11044
[pr-13879]: https://github.com/omacom/omarchy/pull/13879
