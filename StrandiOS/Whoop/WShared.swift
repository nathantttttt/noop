//  WShared.swift
//  Nathan's build: small pieces shared by the WHOOP-style tabs: the scroll tracker that drives the
//  Home dial morph, the floating coach button and its sheet, and the profile avatar.

import SwiftUI
import UIKit

/// Reports how far a ScrollView has scrolled (0 at the top). iOS 18+ reads it straight from the scroll
/// view; on iOS 17 the caller falls back to a geometry preference.
struct WScrollTracker: ViewModifier {
    @Binding var y: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, new in
                y = new
            }
        } else {
            content
        }
    }
}

/// The round coach button that floats bottom-right, like WHOOP's.
struct WCoachButton: View {
    let action: () -> Void
    var body: some View {
        Button {
            WHaptics.tap()
            action()
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(W.hex(0x1A1F2B, 0.75))
                Circle().strokeBorder(
                    AngularGradient(colors: [W.lineBlue, W.purple, W.mint, W.lineBlue], center: .center),
                    lineWidth: 2)
                    .padding(9)
                Image(systemName: "sparkles").font(.system(size: 19, weight: .semibold)).foregroundStyle(W.text)
            }
            .frame(width: 62, height: 62)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(WPressStyle())
        .accessibilityLabel("Ask Coach")
    }
}

/// Coach in a sheet with a Done button. CoachView handles the provider and key setup itself.
struct WCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            CoachView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(W.text)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Profile photo (or initial) in the Home header.
struct WAvatar: View {
    @EnvironmentObject var profile: ProfileStore
    var body: some View {
        Group {
            if let d = profile.avatarImageData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text("N").font(W.num(19)).foregroundStyle(W.text)
            }
        }
        .frame(width: 40, height: 40)
        .background(W.row)
        .clipShape(Circle())
    }
}
