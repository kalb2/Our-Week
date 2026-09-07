# Pushing Builds to TestFlight

## Prerequisites

- **Apple Developer account** enrolled in the Apple Developer Program ($99/yr)
- **Xcode** signed in with your Apple ID (Xcode → Settings → Accounts)
- **App registered** in [App Store Connect](https://appstoreconnect.apple.com) under "My Apps"

---

## Step-by-Step

### 1. Bump the Build Number

Every TestFlight upload requires a **unique build number**. In Xcode:

1. Select the **OurWeek** project (blue icon) in the navigator
2. Select the **OurWeek** target
3. Go to the **General** tab
4. Under **Identity**, increment the **Build** number (e.g. `1` → `2`)
   - The **Version** (e.g. `1.0.0`) only needs to change for new App Store releases

### 2. Set the Destination to "Any iOS Device"

- In the toolbar scheme selector (top‑left), change the destination from a simulator to **Any iOS Device (arm64)**
- This is required — you can't archive a simulator build

### 3. Archive the Build

1. **Product → Archive** (menu bar)
2. Xcode will compile a release build — this takes 1–3 minutes
3. When finished, the **Organizer** window opens automatically showing your new archive

### 4. Distribute to TestFlight

1. In the Organizer, select your archive and click **Distribute App**
2. Choose **TestFlight & App Store** → **Next**
3. Leave defaults (Automatically manage signing) → **Next**
4. Review the summary → **Upload**
5. Wait for the upload to complete (1–5 min depending on app size)

### 5. Wait for Processing

- Go to [App Store Connect](https://appstoreconnect.apple.com) → your app → **TestFlight** tab
- The build will say **"Processing"** for 5–30 minutes
- You'll get an email when it's ready

### 6. Add Testers

Under the **TestFlight** tab in App Store Connect:

- **Internal testers** (up to 100): Add by Apple ID under "Internal Group". They get access immediately.
- **External testers** (up to 10,000): Requires a brief Apple review on the first build. Add by email.

Each tester gets an email/notification to install via the **TestFlight app** on their iPhone.

---

## Quick Reference

| Action | Where |
|---|---|
| Bump build number | Xcode → Target → General → Build |
| Archive | Xcode → Product → Archive |
| Upload | Organizer → Distribute App |
| Manage testers | App Store Connect → TestFlight |

---

## Common Issues

| Problem | Fix |
|---|---|
| **"No accounts with App Store Connect access"** | Ensure your Apple ID has the Admin or App Manager role in App Store Connect |
| **Archive greyed out** | Change destination to "Any iOS Device" — not a simulator |
| **"This bundle is invalid"** | Usually a signing issue — check Signing & Capabilities in the target settings |
| **Build stuck on "Processing"** | Normal for first upload (up to 30 min). If >1 hour, try uploading again |
| **Testers not receiving invite** | Check they have the TestFlight app installed and are using the correct Apple ID |
