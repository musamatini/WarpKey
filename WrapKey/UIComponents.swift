//UIComponents.swift
import SwiftUI
import AppKit

// MARK: - Window Accessor
struct WindowAccessor: NSViewRepresentable {
    var expectedContentSize: CGSize? = nil
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.alphaValue = 0.0
            window.styleMask.remove(.titled)
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            
            if let screenFrame = NSScreen.main?.visibleFrame {
                let finalWindowSize = expectedContentSize ?? window.frame.size
                window.setContentSize(finalWindowSize)
                let newX = screenFrame.midX - (finalWindowSize.width / 2)
                let newY = screenFrame.midY - (finalWindowSize.height / 2)
                window.setFrameOrigin(NSPoint(x: newX, y: newY))
            }
            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            })
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Visual Effects
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BlurredBackgroundView: View {
    var body: some View {
        VisualEffectBlur().overlay(Color.white.opacity(0.01))
    }
}

// MARK: - General UI Components
enum ModifierType {
    case trigger, secondary
}

struct TitleBarButton: View {
    let systemName: String
    let action: () -> Void
    var tintColor: Color?
    var yOffset: CGFloat = 0
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .foregroundColor(tintColor ?? AppTheme.secondaryTextColor)
        }
        .buttonStyle(.plain)
        .offset(y: yOffset)
        .focusable(false)
    }
}

struct CustomTitleBar: View {
    @EnvironmentObject var settings: SettingsManager

    let title: String
    var showBackButton: Bool = false
    var onBack: (() -> Void)? = nil
    var onClose: () -> Void

    private let githubURL = URL(string: "https://github.com/musamatini/WarpKey")!

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if showBackButton {
                TitleBarButton(systemName: "chevron.left", action: { onBack?() }, tintColor: AppTheme.accentColor1)
                    .padding(.trailing, 8)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryTextColor)
            } else {
                if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
                    Image(nsImage: appIcon)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.trailing, 4)
                }
                
                Link(destination: githubURL) {
                    Text(title).font(.headline).fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                
                Menu {
                    ForEach(settings.profiles) { profile in
                        Button(action: { settings.currentProfileID = profile.id }) {
                            if profile.id == settings.currentProfileID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(settings.currentProfile.wrappedValue.name)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.pillBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 150)
                .padding(.leading, 12)
            }
            
            Spacer()
            
            TitleBarButton(systemName: "xmark", action: onClose, tintColor: AppTheme.secondaryTextColor, yOffset: -2)
        }
        .padding(.horizontal)
        .frame(height: 50)
    }
}

struct HelpSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .lineLimit(1)
                .font(.title2.weight(.bold))
                .foregroundColor(AppTheme.primaryTextColor)
                .padding(.bottom, 4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(AppTheme.primaryTextColor.opacity(0.3), lineWidth: 0.7))
    }
}

struct CustomSegmentedPicker<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    private var namespace: Namespace.ID
    private let containerPadding: CGFloat = 4
    private let cornerRadius: CGFloat = AppTheme.cornerRadius

    init(title: String, selection: Binding<T>, in namespace: Namespace.ID) {
        self.title = title
        self._selection = selection
        self.namespace = namespace
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(T.allCases), id: \.self) { option in
                Text(option.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(selection == option ? AppTheme.primaryTextColor : AppTheme.secondaryTextColor)
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: cornerRadius - containerPadding, style: .continuous)
                                    .fill(AppTheme.accentColor1)
                                    .matchedGeometryEffect(id: "picker-highlight", in: namespace)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(containerPadding)
        .background(AppTheme.pickerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PillCard<Content: View>: View {
    let content: Content
    let backgroundColor: Color
    let cornerRadius: CGFloat

    init(@ViewBuilder content: () -> Content, backgroundColor: Color, cornerRadius: CGFloat) {
        self.content = content()
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Custom TextField
class CursorAtEndTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let success = super.becomeFirstResponder()
        if success {
            self.currentEditor()?.selectedRange = NSRange(location: self.stringValue.count, length: 0)
        }
        return success
    }
}

struct URLTextField: NSViewRepresentable {
    @Binding var text: String

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: URLTextField
        init(_ parent: URLTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let textField = CursorAtEndTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.isBordered = true
        textField.backgroundColor = .textBackgroundColor
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}
