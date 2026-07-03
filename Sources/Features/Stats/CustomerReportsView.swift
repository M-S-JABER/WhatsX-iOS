import SwiftUI

struct CustomerReportsView: View {
    @State private var customers: [StatCustomer] = []
    @State private var query = ""
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Group {
                if loading {
                    ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if customers.isEmpty {
                    Text("لا عملاء").foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(customers) { c in
                                NavigationLink {
                                    CustomerReportDetailView(conversationId: c.conversationId, title: c.title)
                                } label: { row(c) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("تقارير العملاء")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(icon: .search).foregroundStyle(Theme.onMuted)
            TextField("ابحث عن عميل", text: $query)
                .foregroundStyle(Theme.onSurface)
                .submitLabel(.search)
                .onSubmit { Task { await load() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
        .onChange(of: query) { _ in Task { await load() } }
    }

    private func row(_ c: StatCustomer) -> some View {
        HStack(spacing: 12) {
            Avatar(name: c.title, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                if let sub = subtitle(c) {
                    Text(sub).font(.caption).foregroundStyle(Theme.onMuted).lineLimit(1)
                }
            }
            Spacer()
            countPill(c.messageCount)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .glassCard(18)
    }

    private func countPill(_ count: Int) -> some View {
        HStack(spacing: 5) {
            Image(icon: .chat).font(.system(size: 11))
            Text("\(count)").font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.primaryContainer, in: Capsule())
    }

    private func subtitle(_ c: StatCustomer) -> String? {
        let parts = [c.phone, c.instanceName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        do { customers = try await Api.shared.statisticsCustomers(search: q.isEmpty ? nil : q).items } catch {}
        loading = false
    }
}
