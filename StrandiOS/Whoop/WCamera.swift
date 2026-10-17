//
//  WCamera.swift
//  NOOP (Nathan's build)
//
//  The progress-photo camera: a self-timer (3, 5 or 10 seconds, counted down out loud and on screen),
//  front/back switch, a faint "ghost" of your last photo to line up the same pose and distance, and the
//  photo library one tap away. The photo is shown back before it is kept.
//

import SwiftUI
import AVFoundation
import AudioToolbox
import PhotosUI

final class WCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "noop.progress-camera")
    private var input: AVCaptureDeviceInput?
    @Published var position: AVCaptureDevice.Position = .back
    @Published var captured: UIImage?
    @Published var denied = false
    @Published var ready = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(position)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.configure(self.position) } else { self.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func flip() {
        position = position == .back ? .front : .back
        configure(position)
    }

    private func configure(_ pos: AVCaptureDevice.Position) {
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let old = self.input { self.session.removeInput(old) }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
               let inp = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(inp) {
                self.session.addInput(inp)
                self.input = inp
            }
            if !self.session.outputs.contains(self.output), self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.ready = self.input != nil }
        }
    }

    func shoot() {
        let front = position == .front
        queue.async {
            if let c = self.output.connection(with: .video) {
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                if c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = front       // a selfie comes out the way the preview showed it
                }
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.captured = img }
    }
}

private struct WCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct WCameraView: View {
    /// Your most recent progress photo, drawn faintly over the viewfinder to match the pose.
    let ghost: UIImage?
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = WCamera()
    @AppStorage("w.camera.timer") private var timer = 0          // seconds, 0 = off
    @AppStorage("w.camera.ghost") private var showGhost = true
    @State private var countdown: Int?
    @State private var countTask: Task<Void, Never>?
    @State private var libraryItem: PhotosPickerItem?
    @State private var flash = false

    private static let timers = [0, 3, 5, 10]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = cam.captured {
                review(img)
            } else {
                viewfinder
            }
        }
        .statusBarHidden()
        .onAppear { cam.start() }
        .onDisappear { countTask?.cancel(); cam.stop() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    onImage(img)
                    dismiss()
                }
                libraryItem = nil
            }
        }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            if cam.denied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 36)).foregroundStyle(W.text3)
                    Text("NOOP doesn't have camera access. Turn it on in Settings → NOOP → Camera, or pick a photo from your library below.")
                        .font(W.body(15)).foregroundStyle(W.text2).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            } else {
                WCameraPreview(session: cam.session).ignoresSafeArea()
                if showGhost, let ghost {
                    Image(uiImage: ghost).resizable().scaledToFill()
                        .scaleEffect(x: cam.position == .front ? -1 : 1, y: 1)
                        .opacity(0.3)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            if let n = countdown {
                Text("\(n)")
                    .font(.system(size: 160, weight: .bold).width(.condensed))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.scale.combined(with: .opacity))
            }
            if flash { Color.white.ignoresSafeArea().transition(.opacity) }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            circleButton("xmark") { dismiss() }
            Spacer()
            Button {
                WHaptics.select()
                let i = Self.timers.firstIndex(of: timer) ?? 0
                timer = Self.timers[(i + 1) % Self.timers.count]
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(timer == 0 ? "OFF" : "\(timer)S").font(W.caps(14))
                }
                .foregroundStyle(timer == 0 ? .white : W.gold)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Color.black.opacity(0.45), in: Capsule())
            }
            .disabled(countdown != nil)
            if ghost != nil {
                Button {
                    WHaptics.select(); showGhost.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.and.background.dotted")
                        Text("GHOST").font(W.caps(14))
                    }
                    .foregroundStyle(showGhost ? W.mint : .white)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Color.black.opacity(0.45), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $libraryItem, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 22))
                    Text("LIBRARY").font(W.caps(10))
                }
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(countdown != nil)
            Spacer()
            Button(action: shutter) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 82, height: 82)
                    if countdown != nil {
                        RoundedRectangle(cornerRadius: 6).fill(W.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.white).frame(width: 66, height: 66)
                    }
                }
            }
            .disabled(cam.denied || !cam.ready)
            Spacer()
            circleButton("arrow.triangle.2.circlepath.camera") { WHaptics.select(); cam.flip() }
                .frame(width: 64)
                .disabled(cam.denied || countdown != nil)
        }
        .padding(.horizontal, 26).padding(.bottom, 24)
    }

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.45), in: Circle())
        }
    }

    // MARK: Timer and capture

    private func shutter() {
        if countdown != nil {               // tap again to cancel the timer
            countTask?.cancel(); countTask = nil
            withAnimation { countdown = nil }
            WHaptics.tap()
            return
        }
        guard timer > 0 else { capture(); return }
        countTask = Task { @MainActor in
            for n in stride(from: timer, through: 1, by: -1) {
                withAnimation(.spring(duration: 0.3)) { countdown = n }
                AudioServicesPlaySystemSound(n <= 3 ? 1113 : 1103)
                WHaptics.tap()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            withAnimation { countdown = nil }
            capture()
        }
    }

    private func capture() {
        cam.shoot()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(.easeIn(duration: 0.25)) { flash = false } }
    }

    // MARK: Review

    private func review(_ img: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 14) {
                Button {
                    WHaptics.tap(); cam.captured = nil
                } label: {
                    Text("RETAKE").font(W.caps(15)).tracking(1.2).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    WHaptics.tap(); onImage(img); dismiss()
                } label: {
                    Text("USE PHOTO").font(W.caps(15)).tracking(1.2).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(W.mint, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
    }
}
