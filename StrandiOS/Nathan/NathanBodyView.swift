//  NathanBodyView.swift
//  Nathan's Body tab: the four goals (resting HR down, HRV up, body fat down, lean mass up) as trend
//  cards, the latest scan readings (Apple Health — the InBody app writes there), and on-device progress
//  photos kept in the app's Documents folder.

import SwiftUI
import Charts
import PhotosUI
import UIKit
import StrandDesign
import WhoopStore

struct NathanBodyView: View {
    @EnvironmentObject var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    enum Range: String, CaseIterable, Identifiable {
        case m1 = "1M", m3 = "3M", m6 = "6M"
        var id: String { rawValue }
        var days: Int { self == .m1 ? 30 : self == .m3 ? 91 : 182 }
    }
    @State private var range: Range = .m1
    @State private var weight: [(day: String, value: Double)] = []
    @State private var bodyFat: [(day: String, value: Double)] = []
    @State private var lean: [(day: String, value: Double)] = []

    private var cutoff: String { Repository.localDayKey(Date().addingTimeInterval(-Double(range.days) * 86_400)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NathanStyle.sectionGap) {
                header
                goals
                leanVsFat
                scan
                NathanProgressPhotos(bodyFatByDay: Dictionary(bodyFat.map { ($0.day, NathanTodayView.pct($0.value)) },
                                                              uniquingKeysWith: { _, b in b }))
            }
            .padding(.horizontal, NathanStyle.page)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(NathanStyle.canvas.ignoresSafeArea())
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) { await load() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST \(range == .m1 ? "30 DAYS" : range == .m3 ? "3 MONTHS" : "6 MONTHS")")
                    .font(NathanStyle.label).tracking(0.8).foregroundStyle(NathanStyle.text3)
                Text("Body").font(.system(size: 30, weight: .heavy)).foregroundStyle(NathanStyle.text)
            }
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
    }

    // MARK: Goals

    private var goals: some View {
        let inRange = repo.days.filter { $0.day >= cutoff }
        let rhr = inRange.compactMap { d in d.restingHr.map { (d.day, Double($0)) } }
        let hrv = inRange.compactMap { d in d.avgHrv.map { (d.day, $0) } }
        let bf = bodyFat.filter { $0.day >= cutoff }.map { ($0.day, NathanTodayView.pct($0.value)) }
        let lm = lean.filter { $0.day >= cutoff }.map { ($0.day, mass($0.value)) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            goalCard("Resting HR", series: rhr, unit: "bpm", better: .down, fmt: NathanFormat.int, dots: false)
            goalCard("HRV", series: hrv, unit: "ms", better: .up, fmt: NathanFormat.int, dots: false)
            goalCard("Body fat", series: bf, unit: "%", better: .down, fmt: NathanFormat.one, dots: true)
            goalCard("Lean mass", series: lm, unit: UnitFormatter.massUnit(units), better: .up, fmt: NathanFormat.one, dots: true)
        }
    }

    private func mass(_ kg: Double) -> Double { units == .imperial ? UnitFormatter.kgToPounds(kg) : kg }

    private func goalCard(_ label: String, series: [(String, Double)], unit: String, better: NathanBetter,
                          fmt: @escaping (Double) -> String, dots: Bool) -> some View {
        let values = series.map { $0.1 }
        // Smooth daily vitals with a 7-day mean at each end so one odd night does not flip the colour.
        let startV = dots ? values.first : NathanFormat.mean(Array(values.prefix(7)))
        let endV = dots ? values.last : NathanFormat.mean(Array(values.suffix(7)))
        let delta = values.count >= 2
            ? NathanDelta.make(current: endV, baseline: startV, better: better, format: fmt,
                               suffix: unit == "%" ? " pts" : " \(unit)", deadband: dots ? 0.05 : 0.5)
            : nil
        let color = delta?.color ?? NathanStyle.text3
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased()).font(NathanStyle.label).tracking(0.6).foregroundStyle(NathanStyle.text3)
                Spacer()
                Text(better == .up ? "goal ▲" : "goal ▼").font(.system(size: 11)).foregroundStyle(NathanStyle.text3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(values.last.map(fmt) ?? "—").font(NathanStyle.number(30)).foregroundStyle(NathanStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if values.last != nil { Text(unit).font(.system(size: 14)).foregroundStyle(NathanStyle.text3) }
            }
            if values.count >= 2 {
                Chart(values.indices.map { NathanPoint(x: $0, y: values[$0]) }) { p in
                    LineMark(x: .value("i", p.x), y: .value(label, p.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    if dots {
                        PointMark(x: .value("i", p.x), y: .value(label, p.y)).foregroundStyle(color).symbolSize(18)
                    }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 36)
            } else {
                Text(values.isEmpty ? "No data yet" : "One reading so far")
                    .font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                    .frame(height: 36, alignment: .leading)
            }
            Text(delta?.text ?? " ").font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NathanStyle.card, in: RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NathanStyle.tileRadius, style: .continuous).stroke(NathanStyle.line, lineWidth: 1))
    }

    // MARK: Lean vs fat

    struct CompPoint: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { series + "\(date.timeIntervalSince1970)" }
    }

    /// Lean mass and fat mass (weight × body fat) on one chart, so muscle going up while fat goes down
    /// reads as the two lines pulling apart.
    private var leanVsFat: some View {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let w = Dictionary(weight.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        let l = Dictionary(lean.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        var pts: [CompPoint] = []
        for b in bodyFat where b.day >= cutoff {
            guard let date = f.date(from: b.day) else { continue }
            let pct = NathanTodayView.pct(b.value)
            if let wk = w[b.day] {
                pts.append(CompPoint(date: date, value: mass(wk * pct / 100), series: "Fat mass"))
                let leanKg = l[b.day] ?? wk * (1 - pct / 100)
                pts.append(CompPoint(date: date, value: mass(leanKg), series: "Lean mass"))
            }
        }
        let shown = pts
        let unit = UnitFormatter.massUnit(units)
        return NathanCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lean mass vs fat mass").font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                    Spacer()
                    Text(unit).font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                }
                if Set(shown.map(\.date)).count >= 2 {
                    Chart(shown) { p in
                        LineMark(x: .value("Day", p.date), y: .value(unit, p.value))
                            .foregroundStyle(by: .value("Series", p.series))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Day", p.date), y: .value(unit, p.value))
                            .foregroundStyle(by: .value("Series", p.series))
                            .symbolSize(22)
                    }
                    .chartForegroundStyleScale(["Lean mass": NathanStyle.good, "Fat mass": NathanStyle.warn])
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartLegend(position: .top, alignment: .leading)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(NathanStyle.line)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(NathanStyle.text3)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(NathanStyle.line)
                            AxisValueLabel().foregroundStyle(NathanStyle.text3)
                        }
                    }
                    .frame(height: 200)
                } else {
                    Text("Needs two scans with weight and body fat in this range.")
                        .font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
                }
            }
        }
    }

    // MARK: Scan

    private var scan: some View {
        let w = weight.last, bf = bodyFat.last, lm = lean.last
        let first = { (s: [(day: String, value: Double)]) in s.first(where: { $0.day >= self.cutoff }) }
        let latestDay = [w?.day, bf?.day, lm?.day].compactMap { $0 }.max()
        let unit = UnitFormatter.massUnit(units)
        var fatMass: Double? = nil
        if let w, let bf { fatMass = mass(w.value) * NathanTodayView.pct(bf.value) / 100 }
        var fatMassStart: Double? = nil
        if let w0 = first(weight), let b0 = first(bodyFat) { fatMassStart = mass(w0.value) * NathanTodayView.pct(b0.value) / 100 }

        return NathanCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(latestDay.map { "Latest scan · \(NathanTodayView.shortDay($0))" } ?? "Latest scan")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(NathanStyle.text)
                    Spacer()
                    Text("vs \(range.rawValue) ago").font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                scanRow("Weight", w.map { mass($0.value) }, first(weight).map { mass($0.value) }, unit, .neither)
                scanRow("Body fat", bf.map { NathanTodayView.pct($0.value) }, first(bodyFat).map { NathanTodayView.pct($0.value) }, "%", .down)
                scanRow("Lean body mass", lm.map { mass($0.value) }, first(lean).map { mass($0.value) }, unit, .up)
                scanRow("Body fat mass", fatMass, fatMassStart, unit, .down)
                if w == nil && bf == nil && lm == nil {
                    Text("No scans yet. In the InBody app turn on Apple Health sharing, then allow NOOP to read Health under More → Apple Health.")
                        .font(.system(size: 13)).foregroundStyle(NathanStyle.text3)
                        .padding(16)
                }
            }
        }
    }

    private func scanRow(_ name: String, _ value: Double?, _ start: Double?, _ unit: String, _ better: NathanBetter) -> some View {
        let d = (value != nil && start != nil && value != start)
            ? NathanDelta.make(current: value, baseline: start, better: better, format: NathanFormat.one, deadband: 0.05) : nil
        return VStack(spacing: 0) {
            Divider().overlay(NathanStyle.line)
            HStack {
                Text(name).font(.system(size: 14)).foregroundStyle(NathanStyle.text2)
                Spacer()
                Text(value.map { NathanFormat.one($0) + (unit == "%" ? "%" : " \(unit)") } ?? "—")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(NathanStyle.text)
                Text(d?.text ?? "—").font(.system(size: 13))
                    .foregroundStyle(d?.color ?? NathanStyle.text3).frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func load() async {
        weight = await repo.series(key: "weight", source: "apple-health", days: 400)
        bodyFat = await repo.series(key: "body_fat", source: "apple-health", days: 400)
        lean = await repo.series(key: "lean_mass", source: "apple-health", days: 400)
    }
}

// MARK: - Progress photos

/// Front-physique photos stored as JPEGs in Documents/ProgressPhotos (on this phone only), each tagged
/// with that day's body fat when a scan exists. Tap one to compare it with the newest.
struct NathanProgressPhotos: View {
    let bodyFatByDay: [String: Double]

    struct Photo: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
        var day: String { Repository.localDayKey(date) }
    }

    @State private var photos: [Photo] = []
    @State private var picked: PhotosPickerItem?
    @State private var comparing: Photo?
    @State private var showCamera = false

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ProgressPhotos", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NathanStyle.gap) {
            NathanSectionHeader(title: "Progress photos", trailing: photos.count >= 2 ? "Tap a photo to compare" : nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    VStack(spacing: 8) {
                        // Tap opens the camera straight away; the library stays one tap below it.
                        Button { showCamera = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera").font(.system(size: 24))
                                Text("Take photo").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(NathanStyle.text2)
                            .frame(width: 104, height: 112)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NathanStyle.text3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        }
                        .buttonStyle(.plain)
                        PhotosPicker(selection: $picked, matching: .images) {
                            Text("From library").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NathanStyle.text3)
                                .frame(width: 104, height: 30)
                        }
                    }
                    ForEach(photos) { p in
                        Button { comparing = p } label: {
                            VStack(spacing: 6) {
                                thumb(p).frame(width: 104, height: 150).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(caption(p)).font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { delete(p) } label: { Label("Delete photo", systemImage: "trash") }
                        }
                    }
                }
            }
            Text("Photos stay on this phone, inside NOOP. Long-press a photo to delete it.")
                .font(.system(size: 12)).foregroundStyle(NathanStyle.text3)
        }
        .task { reload() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await save(item) }
        }
        .sheet(item: $comparing) { p in
            NathanPhotoCompare(older: p, newer: photos.first ?? p, caption: caption)
        }
        .fullScreenCover(isPresented: $showCamera) {
            WCameraPicker { img in store(img) }
                .ignoresSafeArea()
        }
    }

    private func caption(_ p: Photo) -> String {
        let d = p.date.formatted(.dateTime.month(.abbreviated).day())
        if let bf = bodyFatByDay[p.day] { return "\(d) · \(NathanFormat.one(bf))%" }
        return d
    }

    @ViewBuilder private func thumb(_ p: Photo) -> some View {
        if let img = UIImage(contentsOfFile: p.url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Rectangle().fill(NathanStyle.card)
        }
    }

    private func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        photos = urls.filter { $0.pathExtension.lowercased() == "jpg" }.map { url in
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return Photo(url: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    private func save(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        store(img)
    }

    private func store(_ img: UIImage) {
        guard let jpg = img.jpegData(compressionQuality: 0.85) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = Self.folder.appendingPathComponent("front_\(f.string(from: Date())).jpg")
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? jpg.write(to: url, options: .atomic)
        reload()
    }

    private func delete(_ p: Photo) {
        try? FileManager.default.removeItem(at: p.url)
        reload()
    }
}

struct NathanPhotoCompare: View {
    let older: NathanProgressPhotos.Photo
    let newer: NathanProgressPhotos.Photo
    let caption: (NathanProgressPhotos.Photo) -> String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Compare").font(.system(size: 20, weight: .heavy)).foregroundStyle(NathanStyle.text)
                Spacer()
                Button("Done") { dismiss() }.foregroundStyle(NathanStyle.accent)
            }
            HStack(spacing: 10) {
                side(older)
                side(newer)
            }
            Spacer()
        }
        .padding(20)
        .background(NathanStyle.canvas.ignoresSafeArea())
    }

    private func side(_ p: NathanProgressPhotos.Photo) -> some View {
        VStack(spacing: 8) {
            if let img = UIImage(contentsOfFile: p.url.path) {
                Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text(caption(p)).font(.system(size: 13, weight: .semibold)).foregroundStyle(NathanStyle.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The system camera, full screen. Hands back the captured photo; cancel just closes it. Falls back to
/// the photo library on a device without a camera (the simulator).
struct WCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if p.sourceType == .camera { p.cameraDevice = .rear }
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: WCameraPicker
        init(_ parent: WCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
