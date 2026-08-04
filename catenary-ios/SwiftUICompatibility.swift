import SwiftUI

struct CatenaryUnavailableView<LabelContent: View, DescriptionContent: View, ActionsContent: View>: View {
    private let label: LabelContent
    private let description: DescriptionContent
    private let actions: ActionsContent

    init(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent,
        @ViewBuilder actions: () -> ActionsContent
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                label
            } description: {
                description
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 12) {
                label
                    .font(.title3.weight(.semibold))

                description
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                actions
            }
            .multilineTextAlignment(.center)
            .padding()
        }
    }
}

extension CatenaryUnavailableView where ActionsContent == EmptyView {
    init(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent
    ) {
        self.init(
            label: label,
            description: description,
            actions: { EmptyView() }
        )
    }
}

extension CatenaryUnavailableView
where LabelContent == Label<Text, Image>,
      DescriptionContent == EmptyView,
      ActionsContent == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(
            label: { Label(title, systemImage: systemImage) },
            description: { EmptyView() },
            actions: { EmptyView() }
        )
    }
}

extension CatenaryUnavailableView
where LabelContent == Label<Text, Image>,
      DescriptionContent == Text,
      ActionsContent == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text) {
        self.init(
            label: { Label(title, systemImage: systemImage) },
            description: { description },
            actions: { EmptyView() }
        )
    }
}

@available(iOS, introduced: 14.0, obsoleted: 17.0)
private struct LegacyOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void

    @State private var previousValue: Value

    init(value: Value, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.action = action
        _previousValue = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onChange(of: value) { newValue in
            let oldValue = previousValue
            previousValue = newValue
            action(oldValue, newValue)
        }
    }
}

private struct LegacyGeometryChangeModifier<Value: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> Value
    let action: (Value, Value) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let value = transform(proxy)

                Color.clear
                    .onAppear {
                        action(value, value)
                    }
                    .catenaryOnChange(of: value) { oldValue, newValue in
                        action(oldValue, newValue)
                    }
            }
        )
    }
}

extension View {
    @ViewBuilder
    func catenaryOnChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping (Value, Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            modifier(LegacyOnChangeModifier(value: value, action: action))
        }
    }

    @ViewBuilder
    func catenaryOnGeometryChange<Value: Equatable>(
        for type: Value.Type,
        of transform: @escaping (GeometryProxy) -> Value,
        action: @escaping (Value, Value) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onGeometryChange(
                for: type,
                of: transform,
                action: action
            )
        } else {
            modifier(
                LegacyGeometryChangeModifier(
                    transform: transform,
                    action: action
                )
            )
        }
    }

    @ViewBuilder
    func catenaryCircularButtonBorderShape() -> some View {
        if #available(iOS 17.0, *) {
            buttonBorderShape(.circle)
        } else {
            buttonBorderShape(.capsule)
        }
    }
}

extension Animation {
    static var catenaryBouncy: Animation {
        if #available(iOS 17.0, *) {
            return .bouncy
        }
        return .spring(response: 0.4, dampingFraction: 0.78)
    }
}
