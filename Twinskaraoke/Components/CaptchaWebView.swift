import SwiftUI
import WebKit

struct CaptchaWebView: UIViewRepresentable {
  let url: URL
  let onClose: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onClose: onClose)
  }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    let prefs = WKWebpagePreferences()
    prefs.allowsContentJavaScript = true
    config.defaultWebpagePreferences = prefs
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.uiDelegate = context.coordinator
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  class Coordinator: NSObject, WKUIDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) {
      self.onClose = onClose
    }
    func webViewDidClose(_ webView: WKWebView) {
      DispatchQueue.main.async { self.onClose() }
    }
  }
}
