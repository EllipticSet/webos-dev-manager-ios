import SwiftUI

/// Continues the launch screen from Project.json, with the logo in the same place, then fades away.
struct SplashView: View {
  @State private var isTitleVisible = false

  var body: some View {
    ZStack {
      Color("LaunchBackground")
      Image("LaunchLogo")
        .accessibilityHidden(true)
      Text("Dev Manager")
        .font(.title2.bold())
        .foregroundStyle(.white)
        .opacity(isTitleVisible ? 1 : 0)
        .offset(y: 120)
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.smooth(duration: 0.4)) { isTitleVisible = true }
    }
  }
}
