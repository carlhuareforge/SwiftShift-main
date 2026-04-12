import SwiftUI

struct AppView: View {
  var body: some View {
    SettingsView()
      .frame(width: MAIN_WINDOW_WIDTH)
  }
}

#Preview {
  AppView()
}
