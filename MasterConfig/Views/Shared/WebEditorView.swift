import SwiftUI
import WebKit

struct WebEditorView: NSViewRepresentable {
    @Binding var content: String
    var language: String = "markdown"
    var isReadOnly: Bool = false
    var onSave: (() -> Void)?
    var fontSize: Int = 14

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "saveRequested")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "monaco", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastContent != content {
            context.coordinator.pendingContent = content
            context.coordinator.pendingLanguage = language
            context.coordinator.pendingFontSize = fontSize
            if context.coordinator.isReady {
                context.coordinator.applyPendingContent()
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebEditorView
        weak var webView: WKWebView?
        var lastContent: String = ""
        var pendingContent: String = ""
        var pendingLanguage: String = "markdown"
        var pendingFontSize: Int = 14
        var isReady = false

        init(_ parent: WebEditorView) {
            self.parent = parent
            self.pendingContent = parent.content
            self.pendingLanguage = parent.language
            self.pendingFontSize = parent.fontSize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyPendingContent()
        }

        func applyPendingContent() {
            guard let webView else { return }
            let escaped = pendingContent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let readOnly = parent.isReadOnly ? "true" : "false"
            let js = """
                if (typeof window.setEditorContent === 'function') {
                    window.setEditorContent(`\(escaped)`, '\(pendingLanguage)', \(readOnly), \(pendingFontSize));
                }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            lastContent = pendingContent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "contentChanged", let body = message.body as? String {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lastContent = body
                    self.parent.content = body
                }
            } else if message.name == "saveRequested" {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSave?()
                }
            }
        }
    }
}
