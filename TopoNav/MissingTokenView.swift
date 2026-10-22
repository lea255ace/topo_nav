import SwiftUI

/// Shown instead of the map when no Mapbox access token is configured.
struct MissingTokenView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.slash")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Mapbox token missing")
                .font(.title2.bold())

            Text("TopoNav needs a Mapbox public access token to load maps and routes.")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.")
                Text("2. Set `MAPBOX_ACCESS_TOKEN` to your token (starts with `pk.`).")
                Text("3. Clean the build folder (⇧⌘K) and run again.")
            }
            .font(.callout)
            .padding()
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            Text("See the README for how to get a token.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    MissingTokenView()
}
