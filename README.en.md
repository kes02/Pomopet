# 🐾 Pomopet

[한국어](README.md) · **English**

> **The character you upload** wakes up only when you study — a macOS menu bar Pomodoro timer.

Pomopet is a menu bar app that turns your favorite character image into **pixel art** and raises it.
Every time you focus with a Pomodoro session, your character wakes up and your streak grows.
Miss a day and your character falls asleep in grayscale — so **"don't let my character sleep"** becomes your motivation to study.

---

## 🆚 What makes it different from other pet Pomodoro apps

There are plenty of pet-raising Pomodoro apps. Pomopet differs in three ways.

1. **🖼️ Your uploaded image becomes the pet** — Instead of picking from built-in cats and dogs, you **upload your own favorite character** and raise it as pixel art. "Raising your favorite character right in your menu bar" — you'll only find that here.
2. **😴 It falls asleep if you don't show up** — Not just "active while focusing / asleep on breaks." **If you don't hit your daily goal, your character falls asleep in grayscale.** It's designed around loss aversion, like a Duolingo streak — the drive not to lose something you want to keep.
3. **🆓 Free · open source** — No payments, accounts, or subscriptions. All code is public.

> Plus milestone badges (BRONZE→DIAMOND) and an activity heatmap.

---

## 📸 Screenshots

| Character (active) | Settings | Stats · Heatmap |
|:---:|:---:|:---:|
| <img src="docs/screenshots/main.png" width="250" alt="Main"> | <img src="docs/screenshots/settings.png" width="250" alt="Settings"> | <img src="docs/screenshots/stats.png" width="250" alt="Stats"> |

---

## ✨ Features

- **🖼️ Upload your own character** — Drop in a favorite image and it's converted to pixel art for your pet
- **🔥 Streak** — Hit your daily goal to build a streak; break it and it resets
- **😴 Awake / Asleep** — Meet today's goal and your character wakes up in color and bounces; otherwise it sleeps in grayscale
- **🏅 Milestone aura** — A glowing border: 3-day streak BRONZE → 7 SILVER → 30 GOLD → 100 DIAMOND
- **🌱 Activity heatmap** — See the last 35 days of study at a glance
- **🎯 Daily goal** — Set how many sessions a day are needed to "activate" (1–20)
- **🍅 Dead-simple Pomodoro** — Just three settings: focus / break / daily goal
- **🪶 Lightweight** — Lives only in the menu bar (no Dock icon). All graphics are rendered in code, with no external images
- **🔄 Auto-update** — Installs new versions in-app automatically (via [Sparkle](https://sparkle-project.org); details in [Updates](#-updates))
- **🌐 Korean · English** — Follows your system language, or switch it yourself with a button in Settings

---

## 📥 Install

> **Requirements: macOS 14 (Sonoma) or later** · Universal (Apple Silicon + Intel)

### Option 1. Homebrew (recommended)
```bash
brew install --cask kes02/pomopet/pomopet
```
The cask automatically removes the Gatekeeper quarantine attribute, so it runs right away.

### Option 2. Download the DMG directly
1. Download the latest `Pomopet-x.y.z.dmg` from [Releases](https://github.com/kes02/Pomopet/releases)
2. Open the dmg and drag **Pomopet.app** into **Applications**
3. On first launch — since it's an **unsigned build**, macOS blocks it (*"can't verify it's free of malware"*). **On macOS Sequoia (15) the old "right-click → Open" trick is gone.** Pass it one of two ways:
   - **Terminal** (fastest):
     ```bash
     xattr -dr com.apple.quarantine /Applications/Pomopet.app
     ```
   - or **System Settings → Privacy & Security** → scroll down → click **"Open Anyway"** next to "Pomopet was blocked" → launch again and confirm once more

> 💡 In the block dialog, **don't click "Move to Trash"** (it deletes the app) — click "Done" and use one of the methods above. This happens only because there's no Apple signature/notarization; it doesn't affect functionality, and you only need to do it **once**. (Installing via **Homebrew** above skips this entirely.)

### Option 3. Build from source (for developers)
```bash
git clone https://github.com/kes02/Pomopet.git
cd Pomopet
open Pomopet.xcodeproj   # ⌘R in Xcode
# or package a DMG directly:
bash scripts/package-dmg.sh 1.0.0   # → dist/Pomopet-1.0.0.dmg
```

#### Releasing (for maintainers)
```bash
scripts/release.sh 1.2.3   # build DMG → upload GitHub Release → update Homebrew cask (sha256)
```
> Re-generating the DMG changes its hash, so **the release builder is unified into this single script.**
> GitHub Actions (`ci.yml`) only checks that the build doesn't break.

---

## 🔄 Updates

**The app updates itself automatically** (powered by [Sparkle](https://sparkle-project.org) — download, install, and relaunch in one step).

- **In-app auto-update** — When a new version is out, Pomopet notifies you and, with your consent, installs and relaunches right inside the app. You can also check manually with **Check for updates** in Settings.
- **Homebrew users** — You can also update with `brew upgrade --cask pomopet`.

> Updates are verified with an EdDSA signature (tamper-proof even though the build is unsigned), and only version info is fetched (no personal data sent).

---

## 🚀 How to use

1. Click the menu bar icon → **choose a character image to raise**
   - A transparent-background PNG (cutout) looks best — only the character stands out.
2. **Start focus** → when the timer ends, one session is complete
3. Complete today's **daily goal** number of sessions and your character **activates** (wakes up in color) 🔥
4. Keep it up day after day to build your streak and heatmap

### Screen guide
| Button | Function |
|---|---|
| 🐾 | Go to the character screen (home) |
| 📊 | Stats · streak · activity heatmap |
| ⚙️ | Settings (focus/break/daily goal, change character) |

### Settings
- **Focus** — Length of one session (5–60 min)
- **Break** — Rest time after a session (1–30 min)
- **Daily goal** — Sessions needed to activate (1–20)
- **Change character** — Swapping the image keeps your streak intact
- **Language** — Switch between 한국어 / English instantly

> Even if you change the daily goal midway, if you've already met it today your character won't sleep and your streak stays.

---

## 🛠️ Tech stack

- **SwiftUI** · `MenuBarExtra` (menu-bar-only app)
- **SwiftData** — persists daily records and stats
- **Canvas** — pixel rendering without external images (`ImagePixelizer` converts an uploaded image into a color grid)

### Project structure
```
Pomopet/Sources/
├─ App/        App entry point (PomopetApp, menu bar label)
├─ Core/       Timer/streak logic (PomopetController), settings (TimerSettings), update check (UpdateChecker)
├─ Models/     SwiftData models (DailyRecord, AppStats)
├─ Creatures/  Pixel rendering (CustomPet, CharacterView)
└─ Views/      Screens (PopoverView, Stats/Settings)
```

---

## ⚠️ About character images

The upload feature converts a **local image you choose yourself**, for personal use.
If you use someone else's work (characters, etc.), please keep it within personal use. This app bundles and distributes no character images.

---

## 📄 License

[MIT License](LICENSE) © 2026 kes02

> Applies to the app code only. Character images you upload remain the property of their respective copyright holders and are not covered by this license.
