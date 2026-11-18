import SwiftUI
import UIKit

struct ListenTogetherSheet: View {
    let onClose: () -> Void
    @EnvironmentObject private var lt: LtClient

    var body: some View {
        let s = lt.state
        VStack(alignment: .leading, spacing: 0) {
            Text("Listen Together").font(sans: 20, 700).foregroundStyle(Theme.fg)
            Spacer().frame(height: 12)
            if !s.active {
                Text("Fancy a little listen along session with your mates or family? Go ahead and generate a link and enjoy the listening party :)")
                    .font(sans: 15).foregroundStyle(Theme.muted).lineSpacing(5)
                if let e = s.error {
                    Text(e).font(sans: 14).foregroundStyle(Theme.muted).padding(.top, 10)
                }
                Spacer().frame(height: 18)
                pill(s.connecting ? "Starting" : "Start a session", primary: true) { lt.start() }
                    .disabled(s.connecting)
            } else if s.role == "host" {
                Text("You're hosting, \(Format.plural(s.listenerCount, "listener", "listeners"))")
                    .font(sans: 14).foregroundStyle(Theme.fg)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                Spacer().frame(height: 12)
                if let url = URL(string: lt.shareLink) {
                    ShareLink(item: url, subject: Text("Listen with me on SYNK")) {
                        Text("Share link").font(sans: 15, 600).foregroundStyle(Theme.fg)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                    }
                }
                Spacer().frame(height: 8)
                pill("End session", primary: false) { lt.end(); onClose() }
            } else {
                Text("Listening with \(s.hostName)").font(sans: 15).foregroundStyle(Theme.fg)
                Spacer().frame(height: 16)
                pill("Leave session", primary: false) { lt.leave(); onClose() }
            }
            Spacer()
        }
        .padding(20)
        .padding(.top, 8)
    }

    private func pill(_ text: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(sans: 15, 600).foregroundStyle(primary ? Color.black : Theme.fg)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(primary ? Theme.fg : Theme.surface2))
        }
        .buttonStyle(PressStyle())
    }
}
