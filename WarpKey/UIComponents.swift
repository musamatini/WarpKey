// UIComponents.swift
import SwiftUI
import AppKit

struct KeyboardHint: View {
    let key: String
    var body: some View {
        Text("[\(key)]")
            .font(.caption.monospaced())
            .foregroundColor(.secondary)
            .baselineOffset(-1)
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
    
    func customSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        animated: Bool = true,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.overlay(
            ZStack {
                if isPresented.wrappedValue {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPresented.wrappedValue = false
                        }
                        .transition(.opacity)

                    SheetContainer {
                        content()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(
                animated ? .spring(response: 0.4, dampingFraction: 0.8) : nil,
                value: isPresented.wrappedValue
            )
        )
    }
}

struct HoverableTruncatedText: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let font: Font
    let truncationMode: Text.TruncationMode
    let lineLimit: Int

    @State private var idealWidth: CGFloat = 0
    @State private var actualWidth: CGFloat = 0
    @State private var showPopover = false
    @State private var isHovering = false

    private var isTruncated: Bool {
        idealWidth > actualWidth + 1
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(lineLimit)
            .truncationMode(truncationMode)
            .readSize { size in actualWidth = size.width }
            .background(
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: true, vertical: false)
                    .readSize { size in idealWidth = size.width }
                    .hidden()
            )
            .frame(height: 20)
            .onHover { hovering in
                guard isTruncated else { return }
                
                isHovering = hovering
                
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if isHovering {
                            showPopover = true
                        }
                    }
                } else {
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .padding(12)
                }
                .frame(maxWidth: 450, maxHeight: 200)
                .background(BlurredBackgroundView())
            }
    }
}

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
            .overlay { Color.primary.opacity(0.01) }
    }
}

struct HelpSectionBackground: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            VisualEffectBlur()
        } else {
            AppTheme.cardBackgroundColor(for: colorScheme, theme: settings.appTheme)
        }
    }
}

struct HelpSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .lineLimit(1)
                .font(.title2.weight(.bold))
                .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                .padding(.bottom, 4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            HelpSectionBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 0.7)
        }
    }
}

struct CustomSegmentedPicker<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @Binding var selection: T
    private var namespace: Namespace.ID
    private let containerPadding: CGFloat = 4
    var showKeyboardHints: Bool
    
    init(title: String, selection: Binding<T>, in namespace: Namespace.ID, showKeyboardHints: Bool = true) {
        self.title = title
        self._selection = selection
        self.namespace = namespace
        self.showKeyboardHints = showKeyboardHints
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(T.allCases), id: \.self) { option in
                let isSelected = selection == option
                let accentColor = AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)
                let key = (option.rawValue.first?.lowercased()) ?? ""

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5)) {
                        selection = option
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(option.rawValue)
                        if showKeyboardHints {
                            KeyboardHint(key: key.uppercased())
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(isSelected ? AppTheme.adaptiveTextColor(on: accentColor) : AppTheme.secondaryTextColor(for: colorScheme))
                    .background {
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius - containerPadding, style: .continuous)
                                    .fill(accentColor)
                                    .matchedGeometryEffect(id: "picker-highlight", in: namespace)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .if(showKeyboardHints) { view in
                    view.keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
                }
            }
        }
        .padding(containerPadding)
        .background { AppTheme.pickerBackgroundColor(for: colorScheme, theme: settings.appTheme) }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}

struct PillCard<Content: View>: View {
    @EnvironmentObject var settings: SettingsManager
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
            .background { backgroundColor ?? AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CustomSwitchToggleStyle: ToggleStyle {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius * 1.5, style: .continuous)
                    .frame(width: 44, height: 26)
                    .foregroundColor(configuration.isOn ? AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme) : AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .frame(width: 22, height: 22)
                    .foregroundColor(settings.appTheme == .graphite ? Color(white: 0.3) : .white)
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
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background { AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme) }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

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
        Button(action: { showMenu.toggle() }) {
            HStack(spacing: 6) {
                Text(settings.currentProfile.wrappedValue.name)
                    .lineLimit(1)
                    .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                KeyboardHint(key: "P")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { buttonFrame = geo.frame(in: .global) }
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p", modifiers: [])
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(settings.profiles.enumerated()), id: \.element.id) { index, profile in
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
                            if index < 9 {
                                KeyboardHint(key: "\(index + 1)")
                            }
                        }
                        .padding(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .if(index < 9) { view in
                        view.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    }
                }
            }
            .frame(width: max(buttonFrame.width, 160))
            .padding(4)
            .background { AppTheme.cardBackgroundColor(for: colorScheme, theme: settings.appTheme) }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
