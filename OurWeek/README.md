# Antigravity + Xcode Development Guide

This guide explains how to iteratively develop `OurWeek` using Antigravity (your AI assistant) alongside Xcode.

## 🚀 The Workflow

1. **Keep Xcode Open**: Have `OurWeek.xcodeproj` open in Xcode.
2. **Review Code**: Open the file you are working on (e.g., `ContentView.swift`).
3. **Ask Antigravity**: Request changes or new features in the chat.
4. **See Updates**: Watch Xcode update the file automatically.
5. **Verify**: Check the changes in the **Preview Canvas** or **Simulator**.
c
---

## ⚡️ Fast Testing: Xcode Previews

For UI tweaks (colors, layout, text), use **Xcode Previews**.

1. Open `ContentView.swift` in Xcode.
2. Look at the **Canvas** on the right side.
   - *If hidden*: Click the "Adjust Editor Options" button (top-right of editor, icon with lines) -> **Canvas**.
3. **Resume Preview**: If the preview is paused, click the **Refresh/Resume** icon (circular arrow) at the top of the canvas.
4. **Live Updates**: As Antigravity writes code, the preview will refresh automatically.

---

## 📱 Full Testing: Simulator

For testing navigation, data flow, or complex interactions.

1. Select a simulator (e.g., "iPhone 16 Pro") in the top toolbar.
2. Press **Cmd + R** (or the Play button).
3. The app will launch in the simulator window.

> **Tip**: If Antigravity makes changes while the simulator is running, just press **Cmd + R** again to rebuild and relaunch.

---

## 🤖 Example Commands

Try asking Antigravity things like:

- *"Change the 'Good Morning' text to blue."*
- *"Add a new 'Settings' tab to the TabBar."*
- *"Create a new view for the 'Meals' screen and link it."*
- *"Fix the padding on the calendar card."*

Antigravity will edit the code, and you can immediately verify in Xcode!
