import SwiftUI

// Disambiguate the property wrapper from the newer SDK's same-named macro.
private typealias ViewState<Value> = State<Value>

struct CommandShortcutsView: View {
    @ObservedObject var model: AppModel
    let edit: (CommandShortcut?) -> Void
    @ViewState private var pendingDelete: CommandShortcut?
    @ViewState private var error: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("命令快捷方式", systemImage: "terminal").font(.subheadline.weight(.medium))
                Spacer()
                Button { edit(nil) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless).help("添加命令").accessibilityLabel("添加命令")
            }
            if model.commands.isEmpty {
                Button("添加一条命令，点击图标在终端运行") { edit(nil) }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.commands) { command in
                            Button { model.runCommand(command) } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: command.icon).font(.system(size: 22)).foregroundStyle(.indigo)
                                    Text(command.name).font(.caption).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .background(Color.indigo.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .help("\(command.name) · 在终端运行\n\(command.command)")
                            .accessibilityLabel("运行命令：\(command.name)")
                            .contextMenu {
                                Button("编辑命令") { edit(command) }
                                Button("删除命令", role: .destructive) { pendingDelete = command }
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(2, (model.commands.count + 3) / 4)) * 72 - 8)
                Text("点击运行 · 右键编辑或删除").font(.caption2).foregroundStyle(.secondary)
            }
            if let message = error ?? model.commandMessage {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("删除这个命令快捷方式？", isPresented: Binding(get: { pendingDelete != nil },
                                                         set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let command = pendingDelete {
                    do { try model.deleteCommand(command); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                pendingDelete = nil
            }
        } message: { Text(pendingDelete?.name ?? "") }
    }
}

struct CommandEditorView: View {
    @ObservedObject var model: AppModel
    let original: CommandShortcut?
    let close: () -> Void
    @ViewState private var name: String
    @ViewState private var command: String
    @ViewState private var icon: String
    @ViewState private var error: String?

    init(model: AppModel, original: CommandShortcut?, close: @escaping () -> Void) {
        self.model = model
        self.original = original
        self.close = close
        _name = State(initialValue: original?.name ?? "")
        _command = State(initialValue: original?.command ?? "")
        _icon = State(initialValue: original?.icon ?? CommandShortcut.icons[0])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "添加命令快捷方式" : "编辑命令快捷方式").font(.headline)
            TextField("名称，例如：启动项目", text: $name).accessibilityLabel("命令名称")
            HStack(spacing: 10) {
                Text("图标").font(.subheadline)
                ForEach(CommandShortcut.icons, id: \.self) { symbol in
                    Button { icon = symbol } label: {
                        Image(systemName: symbol).frame(width: 32, height: 30)
                            .background(icon == symbol ? Color.indigo.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain).accessibilityLabel("图标：\(symbol)")
                    .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                }
            }
            Text("终端命令").font(.subheadline)
            TextEditor(text: $command).font(.system(.body, design: .monospaced))
                .frame(height: 130).padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                .accessibilityLabel("终端命令")
            Text("点击图标后在系统终端用 zsh 执行，默认从个人主目录开始。可用 cd 指定目录，支持多行命令。保存不会执行。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存") {
                    do {
                        let shortcut = try CommandShortcut(id: original?.id ?? UUID(), name: name, command: command, icon: icon)
                        try model.saveCommand(shortcut)
                        close()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 430).fixedSize(horizontal: true, vertical: true)
    }
}
