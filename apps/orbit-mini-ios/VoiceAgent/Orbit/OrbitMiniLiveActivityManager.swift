import ActivityKit
import Foundation

@MainActor
final class OrbitMiniLiveActivityManager: ObservableObject {
    static let shared = OrbitMiniLiveActivityManager()

    private var activity: Activity<OrbitMiniActivityAttributes>?
    private var lastState: OrbitMiniVoiceState?

    private init() {}

    func reconcileOrphans() async {
        for orphan in Activity<OrbitMiniActivityAttributes>.activities {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
    }

    func begin(userName: String) async {
        guard UserDefaults.standard.object(forKey: "mini.liveActivityEnabled") as? Bool ?? true else { return }
        await reconcileOrphans()
        do {
            activity = try Activity.request(
                attributes: OrbitMiniActivityAttributes(startedAt: .now),
                content: ActivityContent(
                    state: OrbitMiniActivityAttributes.ContentState(state: .listening, userName: userName),
                    staleDate: nil
                ),
                pushType: nil
            )
            lastState = .listening
        } catch {
            // Voice must keep working even if the user disabled Live Activities
            // globally or SideStore has a temporary extension issue.
            activity = nil
            lastState = nil
        }
    }

    func transition(to state: OrbitMiniVoiceState, userName: String) async {
        guard let activity, lastState != state else { return }
        let content = ActivityContent(
            state: OrbitMiniActivityAttributes.ContentState(state: state, userName: userName),
            staleDate: nil
        )
        do {
            let shouldAlert = (state == .listening || state == .speaking)
                && (UserDefaults.standard.object(forKey: "mini.liveActivityBanners") as? Bool ?? true)
            if shouldAlert {
                let alert = AlertConfiguration(title: "ORBIT", body: LocalizedStringResource(stringLiteral: state.title), sound: .default)
                try await activity.update(content, alertConfiguration: alert)
            } else {
                try await activity.update(content)
            }
            lastState = state
        } catch { }
    }

    func end() async {
        let activities = activity.map { [$0] } ?? Activity<OrbitMiniActivityAttributes>.activities
        for current in activities {
            await current.end(
                ActivityContent(state: OrbitMiniActivityAttributes.ContentState(state: .ended, userName: ""), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        activity = nil
        lastState = nil
    }
}
