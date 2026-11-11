import SwiftUI
import AppKit

struct InspectorView: View {
    @ObservedObject var store: CompositionStore
    @State private var customW: String = ""
    @State private var customH: String = ""

    private var selectedIndex: Int? {
        if let idx = store.composition.items.firstIndex(where: { $0.id == store.selectedID }) {
            return idx
        }
        if store.syncPolicyToAll && !store.composition.items.isEmpty {
            return 0
        }
        return nil
    }

    private var selected: ImageItem? {
        guard let idx = selectedIndex else { return nil }
        return store.composition.items[idx]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                directionSection
                    .liquidGlassSection()
                ratioSection
                    .liquidGlassSection()
                policySection
                    .liquidGlassSection()
                globalSection
                    .liquidGlassSection()
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("拼接方向", icon: "rectangle.split.1x2")
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
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("目标比例", icon: "aspectratio")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(RatioPresets.all) { r in
                    ratioChip(r)
                }
            }
            HStack(spacing: 6) {
                TextField("宽", text: $customW)
                    .frame(width: 48)
                    .onSubmit { applyCustomRatio() }
                Text(":").foregroundStyle(.secondary)
                TextField("高", text: $customH)
                    .frame(width: 48)
                    .onSubmit { applyCustomRatio() }
                Spacer()
                Button("应用") {
                    applyCustomRatio()
                }
                .liquidGlassButtonStyle()
                .controlSize(.small)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func applyCustomRatio() {
        if let w = Double(customW), let h = Double(customH), w > 0, h > 0 {
            store.composition.aspectRatio = .custom(w, h)
        }
    }

    private func ratioChip(_ r: AspectRatio) -> some View {
        let isOn = store.composition.aspectRatio.id == r.id
        return Button {
            store.composition.aspectRatio = r
        } label: {
            Text(r.id)
        }
        .buttonStyle(LiquidGlassChipButtonStyle(isSelected: isOn))
    }

    @ViewBuilder
    private var policySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(store.syncPolicyToAll ? "图片策略（全局）" : "选中图片的策略", icon: "crop")
                Spacer()
                Toggle("应用策略到全局", isOn: $store.syncPolicyToAll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            if let item = selected, let idx = selectedIndex {
                let layout = LayoutEngine.layout(store.composition)
                let placement = layout.placements.first { $0.itemID == item.id }
                let dir = placement?.activeAxis(fallback: store.composition.direction) ?? store.composition.direction
                let policy = store.composition.policy(for: item.id)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.syncPolicyToAll
                         ? "当前同步全部 \(store.composition.items.count) 张图片（基准：第 \(idx + 1) 张）"
                         : "第 \(idx + 1) 张：\(item.fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Picker("模式", selection: Binding(
                        get: { policy.mode },
                        set: { store.setMode($0, for: item.id) })) {
                        ForEach(FitMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Picker("对齐", selection: Binding(
                        get: { policy.alignment },
                        set: { store.setAlignment($0, for: item.id) })) {
                        ForEach(CropAlignment.allCases) { a in
                            Text(a.label(for: dir)).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack {
                        Text("可直接在画布拖动单张小图微调位置")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if policy.hasCustomOffset {
                            Button("重置位置") {
                                store.resetOffset(for: item.id)
                            }
                            .liquidGlassButtonStyle()
                            .controlSize(.mini)
                        }
                    }
                }
            } else {
                Text("在画布或左栏点选一张图片")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("画布", icon: "slider.horizontal.3")
            LabeledContent("背景色") {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: store.composition.backgroundColor) },
                    set: { newColor in
                        let ns = NSColor(newColor)
                        store.composition.backgroundColor = (ns.usingColorSpace(.sRGB) ?? ns).cgColor
                    }),
                    supportsOpacity: false)
                    .labelsHidden()
            }
            .font(.caption)
            sliderRow("图片间距", value: $store.composition.gap, range: 0...100)
            sliderRow("外边距", value: $store.composition.margin, range: 0...100)
            Button {
                store.resetToEven()
            } label: {
                Text("重置条带占比为均分")
                    .frame(maxWidth: .infinity)
            }
            .liquidGlassButtonStyle()
            .controlSize(.small)
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

    private func sectionTitle(_ s: String, icon: String) -> some View {
        Label(s, systemImage: icon)
            .font(.subheadline.weight(.semibold))
    }
}
