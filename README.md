![Banner](https://github.com/musamatini/WrapKey/blob/main/banner.png)

# 🎉 WrapKey: Your Mac's Productivity Power-Up! 🚀

### The Ultimate Hotkey Manager for Your Apps, Files, URLs, Scripts, and More.

![Platform](https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white)
![Made with Swift](https://img.shields.io/badge/Made%20with-Swift-F05138?style=flat-square&logo=Swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/musamatini/WrapKey?style=flat-square&logo=github&color=blue)
![Downloads](https://img.shields.io/github/downloads/musamatini/WrapKey/total?style=flat-square&logo=arrow-down-circle&color=brightgreen)
![Stars](https://img.shields.io/github/stars/musamatini/WrapKey?style=flat-square&logo=star&color=gold)

WrapKey is a lightweight yet powerful macOS utility that puts your entire digital life at your fingertips. Create simple, memorable, or complex keyboard shortcuts to launch, switch, or run virtually anything on your Mac. It's designed to be blazing-fast and intuitive, running discreetly from your menu bar to keep you in your creative flow.

<!-- ![WrapKey Demo GIF](path to it) -->

## ✨ Core Features

*   ** Universal Hotkeys:** Forget rigid rules. Assign *any* key combination to *any* action. `⌃+⌥+G` for Google? `F13` for your favorite script? You decide.
*   **🚀 Launch Anything:** Create shortcuts for:
    *   **Apps:** Launch, hide, or bring to the front.
    *   **macOS Shortcuts:** Run any shortcut from Apple's Shortcuts app.
    *   **URLs:** Open websites in your default browser instantly.
    *   **Files & Folders:** Open any file or reveal a folder in Finder.
    *   **Shell Scripts:** Execute commands silently or in a new Terminal window.
*   **⭐ The Instant Cheatsheet:** Lost track of a hotkey? Just press your configurable Cheatsheet shortcut to get a beautiful, organized overlay of all your active shortcuts for the current profile.
*   ** cycled: Advanced App Control:** Don't just launch apps—control them.
    *   **Activate or Hide:** Press a hotkey once to show an app, press it again to hide it.
    *   **Cycle Windows:** If an app has multiple windows, use its hotkey to cycle through them.
*   **🗂️ Profiles:** Create different sets of hotkeys for different contexts like "Work," "Personal," or "Design." Switch between them instantly from the main window.
*   **✏️ Fully Editable:** Edit both the hotkey and the content of your shortcuts at any time. Change a URL, update a script, or re-record a hotkey on the fly.
*   **⚠️ Conflict Detection:** WrapKey intelligently detects when a hotkey is assigned to multiple actions, alerts you with a visual cue, and runs *all* of them when pressed.
*   **🔄 Import & Export:** Easily back up your entire configuration—including all profiles and shortcuts—to a single JSON file. Perfect for migrating to a new Mac.
*   **🎨 Customizable Appearance:** Choose between Light, Dark, or System-matching themes to make WrapKey feel right at home on your desktop.
*   **🪄 Polished & Modern:** A beautiful, intuitive interface, a helpful onboarding experience, and a dedicated help section make getting started a breeze.
*   **⚡ Blazing Fast & Native:** Built 100% in Swift for macOS, ensuring it's lightweight, efficient, and reliable. It uses native Accessibility APIs for maximum performance.
*   **🔄 Automatic Updates:** With Sparkle integration, you'll get the latest features and fixes seamlessly.

<!-- 
    SUGGESTION: Add a screenshot of the main window and the cheatsheet.
-->
| Main Window | Cheatsheet |
| :---: | :---: |
| <!-- <img src="path/to/main_window.png" width="400"> --> | <!-- <img src="path/to/cheatsheet.png" width="400"> --> |
| *Intuitive management for all your shortcuts.* | *Your personal hotkey map, one press away.* |


## 🚀 Getting Started

1.  **[Download `WrapKey.zip`](https://github.com/musamatini/WrapKey/releases/latest)** from the latest release.
2.  Unzip the file and drag **`WrapKey.app`** into your `/Applications` folder.
3.  Launch WrapKey. You will be guided through a one-time setup:
    *   You **must grant Accessibility permissions** when prompted for hotkeys to work.
    *   Follow the Welcome screen for a quick tour.

### How to Use

*   **To Add a Shortcut:**
    1.  Click the WrapKey icon in your menu bar (if enabled) or open the app.
    2.  Click the **`+ Add Shortcut`** button and choose a type (App, URL, Script, etc.).
    3.  Select the item you want to link.
    4.  The **Hotkey Recorder** will appear. Press and hold your desired key combination, then release. Click "Done" to save.

*   **To Use the Cheatsheet:**
    1.  Go to `App Settings` -> `Cheatsheet` to set a global hotkey.
    2.  Press and hold that hotkey anywhere in macOS to see all your shortcuts. Release to hide it.

*   **To Edit a Shortcut:**
    *   In the main window, click the **pencil icon** next to any shortcut. You can choose to **Change Hotkey** or **Edit Content**.

## 👨‍💻 For Developers (Build from Source)

1.  Clone the repo: `git clone https://github.com/musamatini/WrapKey.git`
2.  Open `WrapKey.xcodeproj` in Xcode.
3.  Run the project.

## 🤝 Contribution & Support

WrapKey is an open-source project, and community help is warmly welcomed!

*   **Feedback & Ideas:** If you find a bug or have a feature request, please open an [issue](https://github.com/musamatini/WrapKey/issues).
*   **Contributing Code:** Pull requests are always appreciated! Every contribution helps make WrapKey better.

## ❤️ A Note from the Developer

I'm **Musa Matini**, and WrapKey is a passion project marking my exciting early steps as a junior developer. Building this has been an incredible learning experience, and I'm genuinely thrilled to share it.

Your patience, feedback, and support are truly appreciated as I navigate this journey. Feel free to connect with me at my personal website:
🌐 **[https://musa.matini.link]**

---

Thank you for checking out WrapKey! Happy shortcutting!
