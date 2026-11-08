import SwiftUI
import WebKit

/// Shows an app's HTML description in place, sized to its content so that it scrolls with the page.
struct AppDescriptionView: View {
  var url: URL
  var fallback: String?

  private enum Content {
    case loading
    case loaded(String)
    case failed
  }

  @State private var content = Content.loading
  /// `nil` until the web view has laid out the page, which is slow the first time it starts.
  @State private var height: CGFloat?

  var body: some View {
    Group {
      switch content {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity)
      case .loaded(let html):
        HTMLDescriptionWebView(html: html, baseURL: url, height: $height)
          .frame(height: height ?? 60)
          .overlay {
            if height == nil { ProgressView() }
          }
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
      case .failed:
        Text(fallback ?? String(localized: "Couldn't load the description."))
          .foregroundStyle(fallback == nil ? .secondary : .primary)
      }
    }
    .task(id: url) {
      // Show the saved copy at once, then replace it if the repository has a newer one.
      let cached = DescriptionCache.read(for: url)
      if let cached { content = .loaded(cached) }
      do {
        let html = try await RepositoryClient().fullDescription(at: url)
        DescriptionCache.write(html, for: url)
        if html != cached { content = .loaded(html) }
      } catch is CancellationError {
      } catch {
        if cached == nil { content = .failed }
      }
    }
  }
}

/// A web view for untrusted repository HTML: scripts are off, nothing is stored, and links open in
/// the browser rather than navigating inside the app.
private struct HTMLDescriptionWebView: UIViewRepresentable {
  var html: String
  var baseURL: URL
  @Binding var height: CGFloat?

  @Environment(\.colorScheme) private var colorScheme
  @Environment(AppSettings.self) private var settings

  func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    view.navigationDelegate = context.coordinator
    context.coordinator.observeContentSize(of: view)
    context.coordinator.load(html: document, baseURL: baseURL, into: view)
    return view
  }

  func updateUIView(_ view: WKWebView, context: Context) {
    context.coordinator.height = $height
    context.coordinator.load(html: document, baseURL: baseURL, into: view)
    context.coordinator.measure(view)
  }

  /// The page is as tall as its content, so a lazy image is never scrolled into view and never loads.
  private var eagerHTML: String {
    html.replacing(/\sloading\s*=\s*["']?lazy["']?/.ignoresCase(), with: "")
  }

  /// Only https images may load; the policy also blocks anything else the HTML might try to fetch.
  private var document: String {
    let tint = UIColor(settings.accent).resolvedColor(
      with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    tint.getRed(&red, green: &green, blue: &blue, alpha: nil)
    let link = "rgb(\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255)))"
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https:; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
      <style>
      :root { color-scheme: light dark; }
      html, body { margin: 0; padding: 0; background: transparent; }
      body { font: -apple-system-body; overflow-wrap: anywhere; }
      a { color: \(link); }
      img { max-width: 100% !important; height: auto !important; }
      figure { margin: 0.5em 0; }
      h1 { font: -apple-system-title2; font-weight: 700; }
      h2 { font: -apple-system-title3; font-weight: 600; }
      h3 { font: -apple-system-headline; }
      ul, ol { padding-left: 1.4em; }
      code, pre { font-family: ui-monospace, monospace; font-size: 0.9em; }
      pre { overflow-x: auto; }
      body > :first-child { margin-top: 0; }
      body > :last-child { margin-bottom: 0; }
      </style></head><body>\(eagerHTML)</body></html>
      """
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    var height: Binding<CGFloat?>
    private var loadedDocument: String?
    private var isLoadingDocument = false
    private var contentSizeObservation: NSKeyValueObservation?

    init(height: Binding<CGFloat?>) {
      self.height = height
    }

    func load(html: String, baseURL: URL, into view: WKWebView) {
      guard html != loadedDocument else { return }
      loadedDocument = html
      isLoadingDocument = true
      view.loadHTMLString(html, baseURL: baseURL)
    }

    /// Follows the page as it grows, which images do long after the document has finished loading.
    func observeContentSize(of view: WKWebView) {
      contentSizeObservation = view.scrollView.observe(\.contentSize, options: [.new]) {
        [weak self] _, change in
        guard let value = change.newValue?.height else { return }
        Task { @MainActor in self?.grow(to: value) }
      }
    }

    private func grow(to value: CGFloat) {
      if value > (height.wrappedValue ?? 0) + 1 { height.wrappedValue = value }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      measure(webView)
    }

    /// Asks for the exact height, as the content size is never smaller than the view itself.
    func measure(_ view: WKWebView) {
      view.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
        guard let self, let value = result as? CGFloat, value > 0,
          abs(value - (self.height.wrappedValue ?? 0)) > 1
        else { return }
        self.height.wrappedValue = value
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
      if action.navigationType == .linkActivated, let url = action.request.url {
        if ["http", "https"].contains(url.scheme) { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
      } else if isLoadingDocument {
        isLoadingDocument = false
        decisionHandler(.allow)
      } else {
        // Forms and redirects could otherwise replace the description with another page.
        decisionHandler(.cancel)
      }
    }
  }
}
