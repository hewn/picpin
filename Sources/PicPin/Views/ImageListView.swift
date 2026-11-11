import SwiftUI

struct ImageListView: View {
    @ObservedObject var store: CompositionStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("图片（\(store.composition.items.count)）")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List {
                ForEach(Array(store.composition.items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Image(decorative: item.thumbnail, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(store.selectedID == item.id ? Color.accentColor : .clear,
                                              lineWidth: 2))
                        Text(item.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                        Spacer()
                        Button {
                            store.remove(at: IndexSet(integer: index))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectedID = item.id }
                }
                .onMove { source, destination in store.move(from: source, to: destination) }
                .onDelete { offsets in store.remove(at: offsets) }
            }
            .listStyle(.sidebar)
            if store.lastIgnoredCount > 0 {
                Text("已忽略 \(store.lastIgnoredCount) 个非图片文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }
}
