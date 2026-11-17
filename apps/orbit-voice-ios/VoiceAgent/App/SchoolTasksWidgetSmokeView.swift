#if DEBUG
import SwiftUI

/// Debug-only route used to verify SideStore's signed App Group exchange with
/// synthetic rows. It never reads authentication or real school data.
struct SchoolTasksWidgetSmokeView: View {
    @State private var writeResult: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("WidgetKit · TEST ONLY", systemImage: "checklist")
                .font(.title2.bold())
            Text("Цей екран записує лише фіктивні рядки до App Group. Він не звертається до Orbit API і не читає шкільні дані.")
                .fixedSize(horizontal: false, vertical: true)
            if let writeResult {
                Label(
                    writeResult ? "Тестові дані записано. Додайте віджет «Справи школи» і перевірте small та medium." : "App Group недоступний: запис не вдався.",
                    systemImage: writeResult ? "checkmark.circle" : "xmark.octagon")
                    .foregroundStyle(writeResult ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Записати фіктивні дані") {
                writeResult = SchoolTasksWidgetPublisher.publishSmokeFixture()
            }
            .buttonStyle(.borderedProminent)
            Button("Очистити App Group") {
                SchoolTasksWidgetPublisher.clear()
                writeResult = false
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Widget Smoke Test")
        .task {
            if writeResult == nil {
                writeResult = SchoolTasksWidgetPublisher.publishSmokeFixture()
            }
        }
    }
}
#endif
