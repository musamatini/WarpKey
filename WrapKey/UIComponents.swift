//UIComponenets.swift
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
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .normal
            
            window.styleMask.insert(.borderless)
            window.styleMask.remove(.titled)
            
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true

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
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = colorScheme == .dark ? .popover : .sheet
    }
}

struct BlurredBackgroundView: View {
    var body: some View {
        VisualEffectBlur()
            .overlay(Color.primary.opacity(0.01))
    }
}

// MARK: - General UI Components
struct TitleBarButton: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .foregroundColor(tintColor ?? AppTheme.secondaryTextColor(for: colorScheme))
        }
        .buttonStyle(.plain)
        .offset(y: yOffset)
        .focusable(false)
    }
}

// MARK: - Titles
struct CustomTitleBar: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var showBackButton: Bool = false
    var onBack: (() -> Void)? = nil
    var onClose: () -> Void

    private let githubURL = URL(string: "https://github.com/musamatini/WrapKey")!

    var body: some View {
        HStack(alignment: .center) {
            if showBackButton {
                TitleBarButton(systemName: "chevron.left", action: { onBack?() }, tintColor: AppTheme.accentColor1(for: colorScheme))
                    .padding(.trailing, 4)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                    .padding(.leading, 12)
            } else {
                HStack(spacing: 0) {
                    if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
                        Image(nsImage: appIcon)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    
                    Link(destination: githubURL) {
                        Text(title).font(.headline).fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    
                    ProfileDropdownButton()
                        .padding(.leading, 8)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.leading, 8)
                }
            }
            
            Spacer()
            
            TitleBarButton(systemName: "xmark", action: onClose, tintColor: AppTheme.secondaryTextColor(for: colorScheme), yOffset: -2)
        }
        .padding(.horizontal)
        .frame(height: 50)
    }
}

struct HelpSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .lineLimit(1)
                .font(.title2.weight(.bold))
                .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                .padding(.bottom, 4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            ZStack {
                if colorScheme == .light {
                    AppTheme.cardBackgroundColor(for: colorScheme)
                } else {
                    VisualEffectBlur()
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 0.7))
    }
}

struct CustomSegmentedPicker<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    @Environment(\.colorScheme) private var colorScheme
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
                    .foregroundColor(selection == option ? AppTheme.primaryTextColor(for: colorScheme) : AppTheme.secondaryTextColor(for: colorScheme))
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: cornerRadius - containerPadding, style: .continuous)
                                    .fill(AppTheme.accentColor1(for: colorScheme))
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
        .background(AppTheme.pickerBackgroundColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PillCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    let backgroundColor: Color?
    let cornerRadius: CGFloat

    init(@ViewBuilder content: () -> Content, backgroundColor: Color? = nil, cornerRadius: CGFloat) {
        self.content = content()
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor ?? AppTheme.pillBackgroundColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CustomSwitchToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .frame(width: 44, height: 26)
                    .foregroundColor(configuration.isOn ? AppTheme.accentColor1(for: colorScheme) : AppTheme.pillBackgroundColor(for: colorScheme))
                
                Circle()
                    .frame(width: 22, height: 22)
                    .foregroundColor(.white)
                    .shadow(radius: 1, x: 0, y: 1)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.pillBackgroundColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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

struct ProfileDropdownButton: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMenu = false
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        Button(action: {
            showMenu.toggle()
        }) {
            HStack(spacing: 6) {
                Text(settings.currentProfile.wrappedValue.name)
                    .lineLimit(1)
                    .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.pillBackgroundColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(GeometryReader { geo in
                Color.clear.onAppear {
                    buttonFrame = geo.frame(in: .global)
                }
            })
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(settings.profiles) { profile in
                    Button(action: {
                        settings.currentProfileID = profile.id
                        showMenu = false
                    }) {
                        HStack {
                            if profile.id == settings.currentProfileID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: max(buttonFrame.width, 160))
            .padding(4)
            .background(AppTheme.cardBackgroundColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
