@preconcurrency import ActivityKit
import Foundation
import OSLog

@MainActor
final class OrbitMiniLiveActivityManager: ObservableObject {
    static let shared = OrbitMiniLiveActivityManager()

    private var activity: Activity<OrbitMiniActivityAttributes>?
    private var lastState: OrbitMiniVoiceState?
    private let logger = Logger(subsystem: "net.opik.orbit.mini", category: "live-activity")

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
            logger.notice("Live Activity created")
            // A request alone is not a guaranteed unlocked-screen banner. Ask
            // once for the first real listening state; subsequent alerts are
            // emitted only on meaningful speaker changes.
            await update(activity, to: .listening, userName: userName, shouldAlert: true)
        } catch {
            // Voice must keep working even if the user disabled Live Activities
            // globally or SideStore has a temporary extension issue.
            activity = nil
            lastState = nil
        }
    }

    func transition(to state: OrbitMiniVoiceState, userName: String) async {
        guard let activity, lastState != state else { return }
        let shouldAlert = (state == .listening || state == .speaking)
            && (UserDefaults.standard.object(forKey: "mini.liveActivityBanners") as? Bool ?? true)
        await update(activity, to: state, userName: userName, shouldAlert: shouldAlert)
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

    private func update(
        _ activity: Activity<OrbitMiniActivityAttributes>,
        to state: OrbitMiniVoiceState,
        userName: String,
        shouldAlert: Bool
    ) async {
        let content = ActivityContent(
            state: OrbitMiniActivityAttributes.ContentState(state: state, userName: userName),
            staleDate: nil
        )
        do {
            if shouldAlert {
                logger.notice("Live Activity \(state.rawValue, privacy: .public): alert requested")
                let alert = AlertConfiguration(
                    title: "ORBIT",
                    body: LocalizedStringResource(stringLiteral: state.title),
                    sound: .default
                )
                try await activity.update(content, alertConfiguration: alert)
            } else {
                logger.notice("Live Activity \(state.rawValue, privacy: .public): silent update")
                try await activity.update(content)
            }
            lastState = state
        } catch {
            logger.error("Live Activity update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
