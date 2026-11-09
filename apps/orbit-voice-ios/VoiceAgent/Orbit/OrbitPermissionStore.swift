import Foundation
import SwiftUI

@MainActor
final class OrbitPermissionStore: ObservableObject {
    static let shared = OrbitPermissionStore()
    /// nil until /api/me resolved: write affordances stay visible (adult default) and the backend decides.
    @Published private(set) var permissions: OrbitEffectivePermissions?

    func update(_ contract: OrbitEffectivePermissions?, isMinor: Bool?) {
        if let next = OrbitPermissionPolicy.resolved(contract: contract, isMinor: isMinor) { permissions = next }
    }
    func reset() { permissions = nil }
    func allows(_ permission: OrbitWritePermission) -> Bool { OrbitPermissionPolicy.allows(permission, permissions: permissions) }
}

@MainActor private struct OrbitRequiresModifier: ViewModifier {
    @ObservedObject private var store = OrbitPermissionStore.shared
    let permission: OrbitWritePermission
    func body(content: Content) -> some View {
        if store.allows(permission) { content }
    }
}

extension View {
    /// Shows the control only when the authenticated profile may perform the write (read-only profiles never see it).
    func orbitRequires(_ permission: OrbitWritePermission) -> some View { modifier(OrbitRequiresModifier(permission: permission)) }
}
