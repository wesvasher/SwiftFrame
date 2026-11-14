import SwiftUI

/// The left sidebar: frames deleted from the timeline, newest first, until
/// the bin is emptied. Put them back where they were, or delete them for good.
struct RecycleBinSidebar: View {
    @ObservedObject var model: WindowModel
    @State private var selection: Set<UUID> = []
    @State private var confirmsEmpty = false
    @State private var confirmsDelete: Set<UUID>?

    private var items: [BinnedFrame] { model.recycleBin.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Recycle Bin Is Empty", systemImage: "trash")
                } description: {
                    Text("Deleted frames wait here, so you can put them back.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    Section("Recycle Bin") {
                        ForEach(items) { item in
                            BinRow(model: model, item: item)
                                .tag(item.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Put Back", systemImage: "arrow.uturn.backward") { putBack(ids) }
                    Divider()
                    Button("Delete Permanently…", systemImage: "trash.slash", role: .destructive) {
                        confirmsDelete = ids
                    }
                } primaryAction: { ids in
                    putBack(ids)   // Double-click.
                }
                .onDeleteCommand { confirmsDelete = selection }
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    putBack(selection)
                } label: {
                    Label("Put Back", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .disabled(selection.isEmpty)
                .help("Put the selected frames back where they were in the timeline (or double-click one)")
                Button(role: .destructive) {
                    confirmsEmpty = true
                } label: {
                    Label("Empty", systemImage: "trash.slash").frame(maxWidth: .infinity)
                }
                .disabled(items.isEmpty)
                .help("Delete every frame in the recycle bin")
            }
            .controlSize(.small)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 300)
        .onChange(of: model.recycleBin.map(\.id)) { _, ids in selection.formIntersection(ids) }
        .confirmationDialog("Empty the recycle bin?", isPresented: $confirmsEmpty) {
            Button("Empty Recycle Bin", role: .destructive) { model.emptyRecycleBin() }
        } message: {
            Text("\(count(items.count)) will be deleted. You can undo this until you close the window.")
        }
        .confirmationDialog("Delete permanently?", isPresented: Binding(
            get: { confirmsDelete != nil }, set: { if !$0 { confirmsDelete = nil } })
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let ids = confirmsDelete { model.deleteFromBin(ids) }
            }
        } message: {
            Text("\(count(confirmsDelete?.count ?? 0)) will be deleted. You can undo this until you close the window.")
        }
    }

    private func putBack(_ ids: Set<UUID>) {
        model.restoreFromBin(ids)
        selection.subtract(ids)
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 frame" : "\(n) frames" }
}

private struct BinRow: View {
    @ObservedObject var model: WindowModel
    let item: BinnedFrame

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Color.black
                FramePicture(image: model.images.thumbnail(item.frame.image,
                                                          data: model.document.images[item.frame.image]))
            }
            .frame(width: 56, height: 42)
            .clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame \(item.index + 1)")
                Text(item.deleted, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
