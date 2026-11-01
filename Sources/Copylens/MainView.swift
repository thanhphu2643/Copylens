import SwiftUI

private let brand = Color(red: 0.06, green: 0.46, blue: 0.43) // 5.5:1 against white

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            Form {
                if !model.hasScreenAccess {
                    permissionSection
                }
                recentSection
                settingsSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 600)
        .tint(brand)
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copylens").font(.title2.weight(.semibold))
                    Text("Lấy text từ bất kỳ đâu trên màn hình")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button(action: model.startCapture) {
                HStack {
                    Label("Khoanh vùng để lấy text", systemImage: "text.viewfinder")
                    Spacer()
                    Text("⌘⇧T").monospaced().opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.hasScreenAccess)
        }
    }

    private var permissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Cần quyền Screen Recording", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Copylens cần quyền này để đọc chữ trong vùng bạn khoanh. Ảnh chỉ được xử lý trên máy. Sau khi bật quyền, hãy thoát và mở lại app.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Mở cài đặt quyền", action: model.openScreenRecordingSettings)
            }
            .padding(.vertical, 4)
        }
    }

    private var recentSection: some View {
        Section {
            if model.recents.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Chưa có gì").font(.headline)
                    Text("Nhấn ⌘⇧T rồi kéo chuột quanh đoạn chữ. Text sẽ vào clipboard và hiện ở đây.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                ForEach(model.recents) { item in
                    RecentRow(item: item) { model.copy(item.text) }
                }
            }
        } header: {
            HStack {
                Text("Gần đây")
                Spacer()
                if !model.recents.isEmpty {
                    Button("Xoá hết", action: model.clearRecents)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        } footer: {
            Text("Chỉ lưu tạm trong lúc app chạy, thoát app là mất.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsSection: some View {
        Section("Cài đặt") {
            Toggle(isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin)) {
                Text("Tự chạy khi đăng nhập")
                if let note = loginNote {
                    Text(note)
                }
            }
            .disabled(!model.isInstalled)
            if model.loginNeedsApproval {
                Button("Mở Login Items", action: model.openLoginItemsSettings)
            }
            LabeledContent("Quyền Screen Recording") {
                Label(
                    model.hasScreenAccess ? "Đã cấp" : "Chưa cấp",
                    systemImage: model.hasScreenAccess ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(model.hasScreenAccess ? Color.green : Color.orange)
            }
            LabeledContent("Phiên bản", value: model.version)
            HStack {
                Spacer()
                Button("Thoát Copylens") { NSApp.terminate(nil) }
            }
        }
    }

    private var loginNote: String? {
        if !model.isInstalled { return "Hãy chuyển app vào thư mục Applications để dùng." }
        if model.loginNeedsApproval { return "Cần bật Copylens trong Login Items của macOS." }
        return model.loginError
    }
}

private struct RecentRow: View {
    let item: Extraction
    let copy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(item.date.formatted(date: .omitted, time: .shortened))
                    if item.usedFallback {
                        Label("Không có dấu tiếng Việt", systemImage: "bolt.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                copy()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .help(copied ? "Đã copy" : "Copy lại")
            .accessibilityLabel(copied ? "Đã copy" : "Copy lại")
        }
    }
}
