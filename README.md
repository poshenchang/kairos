# ⌛ Kairos — Student Smart Calendar & Habit Tracker

Kairos is a time management app designed for students to eliminate idle hesitation and decision fatigue. It combines an interactive timetable, deadline tracker, frequency-based habit tracker, and low-friction drag-and-drop scheduling that makes it effortless to pack preparation blocks and habit routines into your week.

---

## ✨ Features Implemented

1. **Weekly & Dynamic Events**
   - Recurring classes, lectures, and gym workouts (RFC 5545 RRULE expansion)
   - One-off events: spontaneous meetings, interviews
   - **Commute / Transportation blocks** (e.g. traveling between hometown and university) with productivity focus mode
   - **Holiday Blackouts & Grouping**: Grouped holidays (e.g. Taiwanese Holidays, US Holidays) with annual recurrence and blackout handling

2. **Deadlines & Task Management**
   - Tracks essays, applications, reports, and weekly problem sets
   - Urgency highlighting:
     - 🔴 **Overdue** (< now)
     - 🟠 **Urgent** (< 24 hours)
     - 🟡 **Warning** (< 72 hours)
   - **Recurring task consolidation:** Weekly problem sets roll over cleanly and only show the next upcoming instance on the dashboard
   - **Subtasks support:** Break complex tasks down and drag individual subtasks onto calendar slots

3. **Multi-Category System**
   - Built-in categories: 🎓 Schoolwork, 💼 Work, 🔬 Research, 🧘 Personal, 🚆 Commute, 👥 Social, 🌐 Other
   - **Custom Category Manager**: Add custom categories with custom icons and color palettes

4. **Frequency-Based Habits (No Hard Deadlines)**
   - Designed for activities like **Personal Research**, **Practicing Instruments (Piano/Violin)**, and **Reading**
   - Set weekly frequency targets (e.g. 3× / week) and preferred time windows (Morning, Afternoon, Evening, Any)
   - Real-time weekly progress bar and quick "+ Log Session" button
   - Automatic habit session completion logging when scheduled slots pass

5. **📅 Interactive Timetable & Semi-Manual Drag Scheduling**
   - **Schedule Sidebar**: Side panel holding uncompleted tasks, subtasks, prep sessions, and habits ready to drag directly onto empty timetable slots
   - **Default Weekly Habit Schedule**: Set up your ideal weekly habit routine (e.g. Monday evening, Wednesday noon) and populate entire weeks with 1 click
   - **Exam & Interview Prep Blocks**: Log-scale prep slider (up to 24 hours) and manual numeric minute input to distribute study and interview prep sessions across preceding days
   - **Conflict Detection & Warnings**: Visual warnings prevent accidentally double-booking conflicting timetable slots
   - **Reminder Events & Notification Controls**: Non-intrusive time-only reminder events and configurable notification reminders ("at start" or custom offsets)

6. **"What to Do Next" Hero Suggestion & Focus Mode**
   - Dashboard dynamically assesses current schedule state and free time remaining
   - Ongoing event awareness: shows active event progress, remaining minutes, and what follows next
   - Suggests highest-leverage uncompleted habits during open time (≥ 30 min)
   - **Focus Timer (Pomodoro)**: 15m, 25m, or 50m timer with visual countdown to jump straight into deep work

---

## 🚀 How to Run (on Linux Desktop)

In your terminal inside `~/Documents/dev/kairos`:

### 1. Generate Drift database code:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 2. Run on Linux desktop:
```bash
flutter run -d linux
```

---

## 📱 Running & Building on iOS

Kairos is fully compatible with iOS. Depending on your setup, you can build and install it either in the cloud (no Mac required) or locally on macOS:

### Option A: Free Cloud Build via Codemagic (No Mac Required)
If you are on Linux or Windows and do not own a Mac, you can build the iOS app completely in the cloud:

1. **Fork this repository** to your GitHub account: [https://github.com/poshenchang/kairos](https://github.com/poshenchang/kairos).
2. **Sign in to [Codemagic](https://codemagic.io)** using your GitHub account (Codemagic offers 500 free macOS build minutes per month).
3. **Select your forked `kairos` repo** in the Codemagic dashboard. The included [`codemagic.yaml`](codemagic.yaml) configuration will be detected automatically.
4. **Build & Install**:
   - **Sideloading (Free)**: Download the compiled `.ipa` file from the build artifacts and sideload it onto your iPhone using [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) with your free Apple ID.
   - **TestFlight**: If you have an Apple Developer membership, link your App Store Connect credentials in Codemagic to automatically deliver builds directly to your phone via TestFlight.

### Option B: Local Build on macOS (with Xcode)
If you have a Mac:

1. Clone the repository:
   ```bash
   git clone https://github.com/poshenchang/kairos.git
   cd kairos
   ```
2. Generate Drift code:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
3. Run on your iPhone or Simulator:
   ```bash
   flutter run -d ios
   ```
   *(Or open `ios/Runner.xcworkspace` in Xcode, select your Personal Team under "Signing & Capabilities", and hit Run).*

---

## 🌐 Running & Installing as a Web App (PWA)

Kairos supports compiling as a Progressive Web App (PWA) using WebAssembly and IndexedDB for local SQLite persistence. You can deploy it to any static web host (such as GitHub Pages, Vercel, Netlify, or Firebase Hosting) and use the browser's native **"Add to Home Screen"** feature on iOS and Android without needing to sideload or go through the App Store.

### Live Web App (GitHub Pages)

Kairos is automatically deployed to GitHub Pages via GitHub Actions:
- **Live App URL**: [https://poshenchang.github.io/kairos/](https://poshenchang.github.io/kairos/)
- **Privacy & Storage**: 100% client-side. All events, tasks, and habits are stored in your device browser's private IndexedDB storage via WebAssembly SQLite. No user data is sent to GitHub or shared between users.

### 1. Build the Web App
```bash
flutter build web --release
```
The compiled static website will be generated in `build/web/`.

### 2. Test Locally
You can test the PWA locally with any static HTTP server (e.g., Python):
```bash
cd build/web
python3 -m http.server 8080
```
Open `http://localhost:8080` in your browser.

### 3. "Add to Home Screen" Installation
- **iPhone / iPad (Safari)**:
  1. Open the hosted Kairos URL in Safari.
  2. Tap the **Share** button (the square with an arrow pointing upward).
  3. Scroll down and tap **Add to Home Screen** (`+`).
  4. Kairos will install as a standalone app on your home screen with its own icon, running in full-screen mode without Safari navigation bars.
- **Android (Chrome)**:
  1. Open the hosted Kairos URL in Chrome.
  2. Tap the **three-dot menu** (⋮) or tap the **"Add Kairos to Home screen"** prompt at the bottom.
  3. Tap **Install app**.

