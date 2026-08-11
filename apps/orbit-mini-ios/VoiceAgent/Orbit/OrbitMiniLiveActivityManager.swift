@preconcurrency import ActivityKit
import Foundation
import OSLog

@MainActor
final class OrbitMiniLiveActivityManager: ObservableObject {
    static let shared = OrbitMiniLiveActivityManager()

    private var activity: Activity<OrbitMiniActivityAttributes>?
    private var lastState: OrbitMiniVoiceState?
    private var transitionID = 0
    private let logger = Logger(subsystem: "net.opik.orbit.mini", category: "live-activity")

    private init() {}

    func reconcileOrphans() async {
        for orphan in Activity<OrbitMiniActivityAttributes>.activities {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
        transitionID = 0
    }

    func begin(userName: String) async {
        guard UserDefaults.standard.object(forKey: "mini.liveActivityEnabled") as? Bool ?? true else { return }
        await reconcileOrphans()
        do {
            let created = try Activity.request(
                attributes: OrbitMiniActivityAttributes(startedAt: .now),
                content: ActivityContent(
                    state: OrbitMiniActivityAttributes.ContentState(state: .listening, userName: userName, transitionID: 0),
                    staleDate: nil
                ),
                pushType: nil
            )
            activity = created
            lastState = nil
            logger.notice("Live Activity created")
            // The initial listening state is intentionally silent. The
            // production default only asks iOS to surface Orbit when it starts
            // answering, avoiding a system haptic on every user turn.
            await update(created, to: .listening, userName: userName, shouldAlert: false)
        } catch {
            // Voice must keep working even if the user disabled Live Activities
            // globally or SideStore has a temporary extension issue.
            activity = nil
            lastState = nil
        }
    }

    func transition(to state: OrbitMiniVoiceState, userName: String) async {
        guard let activity, lastState != state else { return }
        let shouldAlert: Bool
        switch OrbitMiniLiveActivityBannerMode.current {
        case .onlyOrbit:
            shouldAlert = state == .speaking
        case .everySpeakerChange:
            shouldAlert = state == .listening || state == .speaking
        case .off:
            shouldAlert = false
        }
        await update(activity, to: state, userName: userName, shouldAlert: shouldAlert)
    }

    func end() async {
        let activities = activity.map { [$0] } ?? Activity<OrbitMiniActivityAttributes>.activities
        for current in activities {
            await current.end(
                ActivityContent(state: OrbitMiniActivityAttributes.ContentState(state: .ended, userName: "", transitionID: transitionID + 1), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        activity = nil
        lastState = nil
        transitionID = 0
    }

    private func update(
        _ activity: Activity<OrbitMiniActivityAttributes>,
        to state: OrbitMiniVoiceState,
        userName: String,
        shouldAlert: Bool
    ) async {
        transitionID += 1
        let content = ActivityContent(
            state: OrbitMiniActivityAttributes.ContentState(state: state, userName: userName, transitionID: transitionID),
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
