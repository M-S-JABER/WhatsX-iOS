import SwiftUI

/// Design 4k: one «الفريق» screen — users, roles, and templates behind the
/// floating-thumb segmented — replacing three separate settings rows. Each
/// hosted screen keeps its own toolbar actions (add, sync…); only one is
/// mounted at a time, so their toolbars never collide.
struct TeamView: View {
    @State private var tab = "users"

    var body: some View {
        VStack(spacing: 0) {
            GlassSegmented(items: [
                (key: "users", title: L("المستخدمون")),
                (key: "roles", title: L("الأدوار")),
                (key: "templates", title: L("القوالب")),
            ], selection: $tab)
            .padding(.horizontal, 16).padding(.vertical, 10)

            switch tab {
            case "roles": RolesView()
            case "templates": TemplatesView()
            default: UsersView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("الفريق"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
