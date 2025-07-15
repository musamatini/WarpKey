import SwiftUI

struct HelpView: View {
    var goBack: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CustomTitleBar(title: "How to Use", showBackButton: true, onBack: goBack, onClose: { dismiss() })
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HelpSection(title: "Core Actions") {
                        HelpDetailRow(icon: "plus.app.fill", title: "Assign a Shortcut", subtitle: "Bring the app you want to assign to the front. Then, press **Right Option + Right Command + [Letter]**.")
                        HelpDetailRow(icon: "bolt.horizontal.circle.fill", title: "Use a Shortcut", subtitle: "Anywhere in macOS, press **Right Command + [Letter]** to instantly trigger your assigned action.")
                    }
                    HelpSection(title: "Shortcut Modes") {
                        HelpDetailRow(icon: "macwindow.on.rectangle", title: "Hide/Unhide Mode", subtitle: "This is the default mode. If the app is hidden or in the background, this brings it to the front. If it's already in front, it hides the app.")
                        HelpDetailRow(icon: "square.stack.3d.down.forward.fill", title: "Cycle Mode", subtitle: "If an app has multiple windows open (like Finder or a web browser), this mode cycles through each open window every time you use the shortcut.")
                    }
                    HelpSection(title: "Settings Explained") {
                        HelpDetailRow(icon: "menubar.rectangle", title: "Show Menu Bar Icon", subtitle: "Toggles the WarpKey icon in the top system menu bar. If you turn this off, you must re-launch the app to access settings again.")
                        HelpDetailRow(icon: "powersleep", title: "Launch at Login", subtitle: "When enabled, WarpKey will automatically start when you log into your Mac, so your shortcuts are always ready.")
                    }
                }
                .padding()
            }
        }
        .foregroundColor(AppTheme.primaryTextColor)
    }
}

// No changes needed in the views below

struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.bold)).foregroundColor(AppTheme.primaryTextColor).padding(.bottom, 4)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(VisualEffectBlur())
        
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.primaryTextColor.opacity(0.3), lineWidth: 0.7)
                )
    }
}

struct HelpDetailRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title)
                // ✅ FIX: Icon now uses accentColor1 for consistency
                .foregroundColor(AppTheme.accentColor1)
                .frame(width: 40, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundColor(AppTheme.primaryTextColor)
                Text(.init(subtitle)).font(.callout).foregroundColor(AppTheme.secondaryTextColor).lineSpacing(4)
            }
        }
    }
}
