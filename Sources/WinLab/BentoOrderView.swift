import PortalKit
import SwiftUI

/// Ordering from one open bento order, in its own small window: a menu is
/// not enough for dishes with required options.
struct BentoOrderView: View {
    let orderId: String
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @State private var dish: String?
    @State private var single: [String: String] = [:]
    @State private var multiple: [String: Set<String>] = [:]
    @State private var quantity = 1
    @State private var sending = false

    var body: some View {
        if let detail = model.bentoDetail[orderId] {
            Form {
                let categories = detail.menu.map(\.category).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                ForEach(categories, id: \.self) { category in
                    Section(category.isEmpty ? "菜單" : category) {
                        Picker(selection: $dish) {
                            ForEach(detail.menu.filter { $0.category == category }, id: \.id) { item in
                                LabeledContent(item.name, value: "\(Int(item.price)) 元").tag(Optional(item.id))
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                ForEach(detail.optionGroups, id: \.id) { group in
                    Section(group.name + (group.required ? "（必選）" : "")) {
                        if group.multiple {
                            ForEach(group.values, id: \.id) { value in
                                Toggle(label(value), isOn: Binding(
                                    get: { multiple[group.id, default: []].contains(value.id) },
                                    set: { on in
                                        if on { multiple[group.id, default: []].insert(value.id) }
                                        else { multiple[group.id, default: []].remove(value.id) }
                                    }
                                ))
                            }
                        } else {
                            Picker(group.name, selection: Binding(
                                get: { single[group.id] },
                                set: { single[group.id] = $0 }
                            )) {
                                if !group.required { Text("不用").tag(String?.none) }
                                ForEach(group.values, id: \.id) { value in
                                    Text(label(value)).tag(Optional(value.id))
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                    }
                }
                let mine = model.myLines(in: orderId)
                if !mine.isEmpty {
                    Section("我已經點了") {
                        ForEach(mine, id: \.id) { line in
                            LabeledContent(line.name, value: "\(Int(line.price)) 元")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) { footer(detail) }
            .frame(width: 380, height: 520)
        } else {
            ProgressView().frame(width: 380, height: 200)
        }
    }

    private func footer(_ detail: GetBentoOrder.Output) -> some View {
        let missing = detail.optionGroups.filter { $0.required && single[$0.id] == nil && multiple[$0.id, default: []].isEmpty }
        return HStack {
            Stepper("\(quantity) 份", value: $quantity, in: 1 ... 10).fixedSize()
            Spacer()
            if dish != nil, !missing.isEmpty {
                Text("請選\(missing.map(\.name).joined(separator: "、"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("點餐") {
                guard let dish else { return }
                sending = true
                let options = Array(single.values) + multiple.values.flatMap { $0 }
                Task {
                    let ok = await model.order(orderId, item: dish, options: options, quantity: quantity)
                    sending = false
                    if ok { onDone() }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(dish == nil || !missing.isEmpty || sending)
        }
        .padding()
        .background(.bar)
    }

    private func label(_ value: GetBentoOrder.Output.OptionGroup.Value) -> String {
        value.priceDelta == 0 ? value.label : "\(value.label)（+\(Int(value.priceDelta))）"
    }
}
