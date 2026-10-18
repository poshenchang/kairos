# ⌛ Kairos — Student Smart Calendar, Habit Tracker & Auto-Scheduler

Kairos is a time management app designed for students to eliminate idle hesitation and decision fatigue. It combines a smart calendar, deadline tracker, frequency-based habit tracker, and an automated scheduler that intelligently packs preparation blocks and habits into your free time.

---

## ✨ Features Implemented

1. **Weekly & Dynamic Events**
   - Recurring classes, lectures, and gym workouts (RFC 5545 RRULE expansion)
   - One-off events: spontaneous meetings, interviews
   - **Commute / Transportation blocks** (e.g. traveling between hometown and university) with productivity focus mode

2. **Deadlines & Task Management**
   - Tracks essays, applications, reports, and weekly problem sets
   - Urgency highlighting:
     - 🔴 **Overdue** (< now)
     - 🟠 **Urgent** (< 24 hours)
     - 🟡 **Warning** (< 72 hours)
   - **Recurring task consolidation:** Weekly problem sets only show the next upcoming instance on the dashboard

3. **Multi-Category System**
   - Built-in categories: 🎓 Schoolwork, 💼 Work, 🔬 Research, 🧘 Personal, 🚆 Commute, 🌐 Other
   - **Custom Category Manager**: Add custom categories with custom emojis and color palettes

4. **Frequency-Based Habits (No Hard Deadlines)**
   - Designed for activities like **Personal Research**, **Practicing Instruments (Piano/Violin)**, and **Reading**
   - Set weekly frequency targets (e.g. 3× / week) and preferred time windows (Morning, Afternoon, Evening, Any)
   - Real-time weekly progress bar and quick "+ Log Session" button

5. **🤖 Auto-Scheduler Engine**
   - Scans calendar for free gaps (≥ 30 min)
   - **Course & Interview Prep Blocks**: Automatically reserves prep time (e.g. 90-120 min) before high-stakes events (exams, interviews, presentations) distributed across preceding days
   - **Habit Slotting**: Automatically schedules habit sessions in preferred time windows to meet weekly frequency targets
   - Respects sleep / do-not-schedule windows (e.g. 22:00 – 08:00)
   - Manual 1-tap reschedule & background execution

6. **"What to Do Next" Hero Suggestion & Focus Mode**
   - Dashboard dynamically assesses free time remaining before your next event
   - Eliminates time wasting by suggesting the highest-leverage task or habit
   - **Focus Timer (Pomodoro)**: 15m, 25m, or 50m timer with visual countdown to jump straight into deep work

---

## 🚀 How to Run (on Linux Desktop)

In your terminal inside `~/Documents/dev/smart-calender`:

### 1. Generate Drift database code:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 2. Run on Linux desktop:
```bash
flutter run -d linux
```

---

## 📱 Building for iOS (from Linux)

Use the included [`codemagic.yaml`](codemagic.yaml) workflow:
1. Push this repository to GitHub.
2. Sign in to [Codemagic](https://codemagic.io) with GitHub (free tier includes 500 build minutes/month).
3. Connect your repository — Codemagic will build the iOS `.ipa` and deliver it directly to your iPhone via TestFlight!
