import SwiftUI

/// Explains why location is needed when the user has denied access.
struct LocationDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location access is off", systemImage: "location.slash")
                .font(.headline)

            Text("TopoNav needs your location to show where you are on the terrain, follow you as you drive, and plan routes from your position.")
                .font(.callout)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        // Sit above the Mapbox logo and attribution button, which must stay visible.
        .padding(.bottom, 44)
    }
}

#Preview {
    LocationDeniedBanner()
}
