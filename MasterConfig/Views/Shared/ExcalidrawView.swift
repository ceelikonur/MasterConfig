import SwiftUI
import WebKit

struct ExcalidrawView: NSViewRepresentable {
    @Binding var elements: String  // JSON string of Excalidraw elements
    var isReadOnly: Bool = false
    var onSave: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "elementsChanged")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "excalidraw", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastElements != elements && context.coordinator.isReady {
            context.coordinator.setElements(elements)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ExcalidrawView
        weak var webView: WKWebView?
        var lastElements: String = "[]"
        var isReady = false

        init(_ parent: ExcalidrawView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            setElements(parent.elements)
        }

        func setElements(_ json: String) {
            guard let webView else { return }
            let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "`", with: "\\`")
            let js = "if (typeof window.loadElements === 'function') { window.loadElements(`\(escaped)`); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
            lastElements = json
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "elementsChanged", let body = message.body as? String {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lastElements = body
                    self.parent.elements = body
                    self.parent.onSave?(body)
                }
            }
        }
    }
}
