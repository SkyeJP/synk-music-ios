import SwiftUI
import WebKit

/// Settings row that connects Discord, so SYNK can show what you play in your Discord status.
struct DiscordRow: View {
    @State private var username: String?
    @State private var showLogin = false
    @State private var confirmOff = false

    var body: some View {
        Button { if username == nil { showLogin = true } else { confirmOff = true } } label: {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Discord").font(sans: 15, 500).foregroundStyle(Theme.fg)
                        Text(username.map { "Showing what you play as \($0)" } ?? "Show what you play in your Discord status, on every device")
                            .font(sans: 12).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(username == nil ? "Log In" : "Disconnect").font(sans: 13, 600).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            let o = try? await API.shared.json("discord")
            username = o?["connected"] as? Bool == true ? (o?["username"] as? String ?? "Discord") : nil
        }
        .sheet(isPresented: $showLogin) { DiscordLoginSheet { username = $0 } }
        .confirmationDialog("Disconnect Discord?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task {
                    try? await API.shared.sendVoid("discord", method: "DELETE")
                    username = nil
                }
            }
        }
    }
}

struct DiscordLoginSheet: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DiscordWebView { token in Task { await save(token) } }
                if saving {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    Spinner()
                }
            }
            .navigationTitle("Log In With Discord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Couldn't connect Discord", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(error ?? "")
            }
        }
    }

    @MainActor private func save(_ token: String) async {
        guard !saving else { return }
        saving = true
        do {
            let d = try await API.shared.data(API.shared.request("discord", method: "POST", body: ["token": token]))
            let name = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["username"] as? String ?? "Discord"
            onDone(name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}

/// discord.com's own login page, so Discord's captcha and two-factor work as normal.
/// Nothing is kept after the sheet closes; the login is read from the first signed-in request.
struct DiscordWebView: UIViewRepresentable {
    var onToken: (String) -> Void

    private static let hook = """
    (function () {
      var sent = false;
      function grab(v) {
        if (sent || typeof v !== 'string' || v.length < 30 || v.indexOf('Bot ') === 0 || v.indexOf('Bearer ') === 0) return;
        sent = true;
        window.webkit.messageHandlers.synk.postMessage(v);
      }
      var set = XMLHttpRequest.prototype.setRequestHeader;
      XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
        if (String(k).toLowerCase() === 'authorization') grab(v);
        return set.apply(this, arguments);
      };
      var f = window.fetch;
      window.fetch = function (input, init) {
        try {
          var h = init && init.headers;
          var v = h && (typeof h.get === 'function' ? h.get('Authorization') : (h.Authorization || h.authorization));
          if (v) grab(v);
        } catch (e) {}
        return f.apply(this, arguments);
      };
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.addUserScript(WKUserScript(source: Self.hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator, name: "synk")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.load(URLRequest(url: URL(string: "https://discord.com/login")!))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "synk")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let t = message.body as? String { onToken(t) }
        }
    }
}
