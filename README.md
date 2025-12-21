# Refocus

You open Chrome to check one thing. Two hours later you're deep in YouTube/Twitter/Reddit.

Refocus stops this. Start a work session, and if you drift to a distracting site, you get a warning. Ignore it, and a full-screen overlay blocks everything. Enable hard mode, and Chrome closes entirely.

No willpower required. The app enforces it for you.

## How it works

1. Start a session from the menu bar
2. Work normally in Chrome
3. Visit youtube.com or twitter.com → warning overlay appears
4. Switch to an allowed site → overlay disappears
5. Ignore the warning → screen goes red, Chrome closes (hard mode)

## Setup

```bash
./scripts/reinstall_refocus_app.sh
./scripts/install_native_host.sh
```

Then load the Chrome extension from `chrome://extensions` → Load unpacked → `chrome_extension/`

## Privacy

Everything stays on your Mac. No accounts, no cloud, no tracking.
