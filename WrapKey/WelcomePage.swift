import SwiftUI

struct WelcomePage: View {
    @EnvironmentObject var settings: SettingsManager
    var onGetStarted: () -> Void

    @State private var isShowingContent = false
    
    // --- URLs for the links ---
    private let donationURL = URL(string: "https://www.buymeocoffee.com/yourusername")!
    private let githubURL = URL(string: "https://github.com/your-username/your-repo/issues")!

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 35) {
                
                // MARK: - Title Block
                VStack(spacing: 15) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 50, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        // ✅ FIX: Sparkles icon now uses accentColor1
                        .foregroundStyle(AppTheme.accentColor1)

                    Text("Welcome to WarpKey")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }
                .opacity(isShowingContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: isShowingContent)
                
                // MARK: - Core Actions
                VStack(alignment: .leading, spacing: 25) {
                    WelcomeActionRow(
                        icon: "plus.app.fill",
                        title: "Assign a Shortcut",
                        subtitle: "Use **R-Opt + R-Cmd + [Letter]** when an app is frontmost."
                    )
                    WelcomeActionRow(
                        icon: "bolt.horizontal.circle.fill",
                        title: "Use a Shortcut",
                        subtitle: "Press **R-Cmd + [Letter]** to launch or hide."
                    )
                }
                .padding(.horizontal, 40)
                .opacity(isShowingContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.7).delay(0.1), value: isShowingContent)

                // MARK: - "How to Use" Link
                (
                    Text("Feeling confused? Check the ")
                    +
                    Text("How to Use")
                        .bold()
                        // ✅ FIX: This link highlight now uses accentColor1
                        .foregroundColor(AppTheme.accentColor1)
                        .underline()
                    +
                    Text(" page.")
                )
                .font(.callout)
                .foregroundColor(AppTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .onTapGesture {
                    print("[WelcomePage] Tapped 'How to Use' link.")
                    NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil)
                    settings.hasCompletedOnboarding = true
                    onGetStarted()
                }
                .opacity(isShowingContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.7).delay(0.2), value: isShowingContent)

                // MARK: - Support & Feedback Links
                VStack(spacing: 18) {
                    Link(destination: githubURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "ant.circle.fill")
                            Text("Report a bug or suggest a feature")
                        }
                    }
                    
                    Link(destination: donationURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.circle.fill")
                            Text("Support me and the project")
                        }
                    }
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.secondaryTextColor.opacity(0.8))
                .opacity(isShowingContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.7).delay(0.3), value: isShowingContent)
            }
            
            Spacer()

            // MARK: - Footer section (Button Only)
            Button(action: {
                print("[WelcomePage] 'Get Started' button clicked. Setting hasCompletedOnboarding to true.")
                settings.hasCompletedOnboarding = true
                onGetStarted()
            }) {
                Text("Continue to App")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .foregroundColor(AppTheme.primaryTextColor)
                    // ✅ FIX: Background color is now accentColor1
                    .background(AppTheme.accentColor1)
                    .cornerRadius(50)
            }
            .buttonStyle(.plain)
            .opacity(isShowingContent ? 1 : 0)
            .animation(.easeInOut(duration: 0.7).delay(0.4), value: isShowingContent)
            .padding(.bottom, 50)
        }
        .frame(width: 450, height: 700)
        .foregroundColor(AppTheme.primaryTextColor)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isShowingContent = true
            }
        }
    }
}

// WelcomeActionRow and other supporting structs remain unchanged,
// as they correctly use the AppTheme colors.
struct WelcomeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                // ✅ FIX: Icon now uses accentColor1 for more prominence
                .foregroundColor(AppTheme.accentColor1)
                .frame(width: 30) // Ensures alignment between rows
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryTextColor)
                
                // Using .init() to render Markdown for bold text
                Text(.init(subtitle))
                    .font(.callout)
                    .foregroundColor(AppTheme.secondaryTextColor)
            }
        }
    }
}
