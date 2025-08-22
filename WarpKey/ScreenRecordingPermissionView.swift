// ScreenRecordingPermissionView.swift

import SwiftUI

struct ScreenRecordingPermissionView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "rectangle.on.rectangle.angled.fill")
                        .font(.system(size: 50, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    
                    Text("Enhanced Window Switching")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                
                VStack(spacing: 12) {
                    Text("To switch to apps on other desktops or in fullscreen, WarpKey needs Screen Recording permission.")
                    
                    Text("**WarpKey never records your screen.** macOS bundles the permission to see windows across all spaces under \"Screen Recording\".")
                        .font(.footnote)
                        .padding(10)
                        .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(AppTheme.cornerRadius)
                    
                    Text("1. Click **Open System Settings**.\n2. Find **WarpKey** in the list and turn it on.\n3. Return here and click **Relaunch App**.")
                }
                .font(.callout)
                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 40)
            }
            Spacer()
            VStack(spacing: 16) {
                Button(action: { AccessibilityManager.requestScreenRecordingPermissions() }) {
                    Text("Open System Settings")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40).padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [])
                
                Button(action: { NotificationCenter.default.post(name: .requestAppRestart, object: nil) }) {
                    Text("Relaunch App")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [])
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 50)
        }
        .background(AppTheme.background(for: colorScheme, theme: settings.appTheme).ignoresSafeArea())
    }
}
