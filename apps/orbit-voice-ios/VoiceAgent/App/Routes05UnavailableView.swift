import SwiftUI

/// Truthful native state for a manifest route without an authorized capability.
/// It is intentionally not a success-looking placeholder or demo data surface.
struct Routes05UnavailableView: View {
    let routeID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Routes05ContextHeader(
                    section: "discovery",
                    eyebrow: "ROUTES / NOT AVAILABLE",
                    title: "Ще не\nпідключено.",
                    detail: "Цей розділ є в дизайн-маніфесті, але для нього немає авторизованої можливості в поточній збірці.",
                    accent: Routes05Tokens.lilac
                )
                Routes05StateRow(text: "Маршрут: \(routeID). Дані не вигадуються.", tint: Routes05Tokens.lilac)
            }
            .padding(.bottom, 24)
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .routes05ContextSurface()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
