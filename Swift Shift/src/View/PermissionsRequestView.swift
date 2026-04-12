import SwiftUI

struct PermissionRequestView: View {
  let permissionState: PermissionState
  let refreshPermissions: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Permissions Required")
          .font(.system(size: 13, weight: .semibold))
      }

      VStack(alignment: .leading, spacing: 8) {
        if !permissionState.accessibility {
          permissionRow(
            title: "Accessibility",
            detail: "Manage windows across apps.",
            icon: "figure.wave",
            buttonTitle: "Grant Accessibility"
          ) {
            PermissionsManager.requestAccessibilityPermission()
            PermissionsManager.openPreferences(at: .accessibility)
            refreshPermissions()
          }
        }

        if !permissionState.inputMonitoring {
          permissionRow(
            title: "Input Monitoring",
            detail: "Listen for your global shortcuts.",
            icon: "keyboard.badge.eye",
            buttonTitle: "Grant Input Monitoring"
          ) {
            let granted = PermissionsManager.requestInputMonitoringPermission()
            if !granted {
              PermissionsManager.openPreferences(at: .inputMonitoring)
            }
            refreshPermissions()
          }
        }
      }
    }
    .padding(12)
    .background(.orange.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  @ViewBuilder
  private func permissionRow(title: String, detail: String, icon: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundStyle(.orange)
          .frame(width: 14)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.system(size: 12, weight: .semibold))
          Text(detail)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Button(action: action) {
        HStack(spacing: 4) {
          Image(systemName: "lock.open")
          Text(buttonTitle)
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.orange)
    }
  }
}

#Preview {
  PermissionRequestView(
    permissionState: PermissionState(accessibility: false, inputMonitoring: false),
    refreshPermissions: {}
  )
  .padding()
  .frame(width: 300)
}
