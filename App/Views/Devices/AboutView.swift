import SwiftUI

struct AboutView: View {
  var body: some View {
    Form {
      Section {
        VStack(spacing: 12) {
          Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .background(Color("LaunchBackground"), in: .rect(cornerRadius: 22))
            .accessibilityHidden(true)
          Text("Version \(version)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("Dev Manager is a companion app for LG webOS TVs in Developer Mode or with root access. Manage your TV from your iPhone over your local network.")
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
      }
      Section("What You Can Do") {
        Label("Install, update, and open apps, including from the Homebrew catalog", systemImage: "square.grid.2x2")
        Label("Browse, upload, and download files", systemImage: "folder")
        Label("Open a terminal on your TV", systemImage: "apple.terminal")
        Label("Check TV details and renew your Developer Mode session", systemImage: "info.circle")
        Label("View logs and crash reports, and monitor the Luna bus", systemImage: "ladybug")
      }
      Section {
        Text("Dev Manager is an independent developer tool. It isn't affiliated with, sponsored by, or approved by LG Electronics or the webOS Homebrew project. webOS is a trademark of its respective owners.")
      }
      Section("Privacy") {
        Text("This app doesn't collect data. Credentials stay in this iPhone's keychain and are used only to connect to your TVs.")
      }
      Section("Services Used") {
        Text("repo.webosbrew.org for the Homebrew catalog, and developer.lge.com for Developer Mode status and renewal.")
      }
      Section("Acknowledgments") {
        Link("Based on Device/DevMode Manager for webOS TV by webosbrew (Apache 2.0)", destination: URL(string: "https://github.com/webosbrew/dev-manager-desktop")!)
        Link("Citadel (MIT)", destination: URL(string: "https://github.com/orlandos-nl/Citadel")!)
        Link("SwiftTerm (MIT)", destination: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
        Link("Swift NIO SSH (Apache 2.0)", destination: URL(string: "https://github.com/apple/swift-nio-ssh")!)
      }
    }
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
  }
}
