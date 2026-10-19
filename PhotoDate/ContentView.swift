import SwiftUI
import PhotosUI
import Photos

private struct SelectedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    var date: Date?
    let source: String
}

struct ContentView: View {
    @State private var selection: [PhotosPickerItem] = []
    @State private var photos: [SelectedPhoto] = []
    @State private var corner: StampCorner = .right
    @State private var busy = false
    @State private var message: String?
    @State private var progress = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("あの日を、写真に。").font(.largeTitle.bold())
                        Text("フィルムカメラのような、あたたかな日付を。\n元の写真は変えず、新しい写真として保存します。")
                            .foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .images,
                                 preferredItemEncoding: .current) {
                        Label(photos.isEmpty ? "写真を選ぶ" : "写真を選び直す", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent).tint(.orange).disabled(busy)

                    if !photos.isEmpty {
                        Picker("日付の位置", selection: $corner) {
                            ForEach(StampCorner.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).disabled(busy)

                        ForEach($photos) { $photo in
                            VStack(alignment: .leading, spacing: 10) {
                                Image(uiImage: preview(photo))
                                    .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                                if let date = photo.date {
                                    HStack {
                                        Text(DateStamp.label(for: date)).monospacedDigit()
                                        Spacer()
                                        Text(photo.source).font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("撮影日が見つかりません。日付を指定してください。")
                                        .font(.callout).foregroundStyle(.orange)
                                }
                                DatePicker("日付を指定", selection: Binding(
                                    get: { photo.date ?? DateStamp.calendarDay(Date()) },
                                    set: { photo.date = $0 }
                                ), displayedComponents: .date)
                                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                                .disabled(busy)
                                if photo.date == nil {
                                    Button("今日の日付を使う") { photo.date = DateStamp.calendarDay(Date()) }
                                        .disabled(busy)
                                }
                            }
                        }
                        Button(action: { Task { await save() } }) {
                            Label("\(photos.count)枚を日付入りで保存", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity).padding()
                        }.buttonStyle(.borderedProminent).tint(.orange)
                            .disabled(busy || photos.contains { $0.date == nil })
                    }
                    if busy { ProgressView(progress).frame(maxWidth: .infinity) }
                    Text("写真は端末内で処理されます。外部へのアップロードはありません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Photo Date")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selection) { _, items in Task { await load(items) } }
            .alert("Photo Date", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func preview(_ photo: SelectedPhoto) -> UIImage {
        // Keep previews small; full resolution rendering happens only during export.
        let scale = min(1, 900 / max(photo.image.size.width, photo.image.size.height))
        let size = CGSize(width: photo.image.size.width * scale, height: photo.image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let date = photo.date else { return thumbnail }
        return DateStamp.render(thumbnail, date: date, corner: corner)
    }

    @MainActor private func load(_ items: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false }
        photos = []
        var failures = 0
        for (index, item) in items.enumerated() {
            progress = "写真を読み込み中 \(index + 1) / \(items.count)"
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { failures += 1; continue }
                var date = DateStamp.metadataDate(in: data)
                var source = "撮影メタデータ"
                // Library dates also cover screenshots without embedded EXIF dates.
                var libraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if date == nil && libraryStatus == .notDetermined {
                    libraryStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                }
                if date == nil, (libraryStatus == .authorized || libraryStatus == .limited),
                   let identifier = item.itemIdentifier,
                   let created = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.creationDate {
                    date = DateStamp.calendarDay(created)
                    source = "写真ライブラリの作成日"
                }
                photos.append(SelectedPhoto(image: image, date: date, source: date == nil ? "手動指定" : source))
            } catch { failures += 1 }
        }
        if failures > 0 { message = "\(failures)枚の写真を読み込めませんでした。端末にダウンロード済みの写真で再度お試しください。" }
    }

    @MainActor private func save() async {
        busy = true
        defer { busy = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = "写真の保存が許可されていません。iPhoneの設定で Photo Date の写真追加を許可してください。"
            return
        }
        var saved = 0
        for photo in photos {
            guard let date = photo.date else { continue }
            progress = "保存中 \(saved + 1) / \(photos.count)"
            let data: Data? = autoreleasepool {
                DateStamp.render(photo.image, date: date, corner: corner).jpegData(compressionQuality: 0.95)
            }
            guard let data else { message = "画像を生成できませんでした。\(saved)枚は保存済みです。"; return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
                saved += 1
            } catch {
                message = "保存できませんでした。\(saved)枚は保存済みです。空き容量と写真へのアクセス許可をご確認ください。"
                return
            }
        }
        message = "\(saved)枚を写真ライブラリに保存しました。"
    }
}
