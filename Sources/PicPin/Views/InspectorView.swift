import SwiftUI
import AppKit

struct InspectorView: View {
    @ObservedObject var store: CompositionStore
    @State private var customW: String = ""
    @State private var customH: String = ""

    private var selected: ImageItem? {
        store.composition.items.first { $0.id == store.selectedID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                directionSection
                ratioSection
                policySection
                globalSection
            }
            .padding(12)
        }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("拼接方向")
            Picker("拼接方向", selection: $store.composition.direction) {
                ForEach(StitchDirection.allCases) { d in
                    Text(d.label).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("目标比例")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(RatioPresets.all) { r in
                    ratioChip(r)
                }
            }
            HStack {
                TextField("宽", text: $customW).frame(width: 52)
                Text(":")
                TextField("高", text: $customH).frame(width: 52)
                Button("应用") {
                    if let w = Double(customW), let h = Double(customH), w > 0, h > 0 {
                        store.composition.aspectRatio = .custom(w, h)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func ratioChip(_ r: AspectRatio) -> some View {
        let isOn = store.composition.aspectRatio.id == r.id
        return Button {
            store.composition.aspectRatio = r
        } label: {
            Text(r.id)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var policySection: some View {
        sectionTitle("选中图片的策略")
        if let item = selected {
            let dir = store.composition.direction
            let policy = store.composition.policy(for: item.id)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Picker("模式", selection: Binding(
                    get: { policy.mode },
                    set: { store.composition.policies[item.id] =
                        SlicePolicy(mode: $0, alignment: policy.alignment) })) {
                    ForEach(FitMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("对齐", selection: Binding(
                    get: { policy.alignment },
                    set: { store.composition.policies[item.id] =
                        SlicePolicy(mode: policy.mode, alignment: $0) })) {
                    ForEach(CropAlignment.allCases) { a in
                        Text(a.label(for: dir)).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } else {
            Text("在画布或左栏点选一张图片")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("画布")
            LabeledContent("背景色") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: store.composition.backgroundColor) },
                    set: { store.composition.backgroundColor = NSColor($0).cgColor }),
                    supportsOpacity: false)
                    .labelsHidden()
            }
            sliderRow("图片间距", value: $store.composition.gap, range: 0...100)
            sliderRow("外边距", value: $store.composition.margin, range: 0...100)
            Button("重置为均分") { store.resetToEven() }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.0f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline)
    }
}
