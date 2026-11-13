import SwiftUI

struct ImageListView: View {
    @ObservedObject var store: CompositionStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("图片（\(store.composition.items.count)）")
                    .font(.headline)
                Spacer()
                Button {
                    store.openImagePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassButtonStyle()
                .controlSize(.small)
                .keyboardShortcut("o", modifiers: .command)
                .help("添加图片 (⌘O)")

                if !store.composition.items.isEmpty {
                    Button {
                        store.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .help("清空全部图片")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List {
                ForEach(Array(store.composition.items.enumerated()), id: \.element.id) { index, item in
                    let isSelected = store.selectedID == item.id
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .frame(width: 18)
                        Image(decorative: item.listIcon, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.18),
                                                  lineWidth: isSelected ? 2 : 0.8)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                            Text("\(Int(item.pixelSize.width)) × \(Int(item.pixelSize.height))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            store.remove(at: IndexSet(integer: index))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectedID = item.id }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { source, destination in store.move(from: source, to: destination) }
                .onDelete { offsets in store.remove(at: offsets) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if store.lastIgnoredCount > 0 {
                Text("已忽略 \(store.lastIgnoredCount) 个非图片文件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Divider()
                .opacity(0.3)
            Button {
                AboutPanel.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("vibe by hewN with GLM & Gemini")
                            .font(.system(size: 10, weight: .medium))
                        Text("weibo@heptagonal")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关于 PicPin")
        }
    }
}
