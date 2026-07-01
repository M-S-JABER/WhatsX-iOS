import SwiftUI

struct NewConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var instances: [Instance] = []
    @State private var selectedId: String?
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("محادثة جديدة").font(.title3.bold()).foregroundStyle(Theme.onSurface)

                HStack(spacing: 10) {
                    Image(icon: .call).foregroundStyle(Theme.onFaint)
                    TextField("+9647xxxxxxxxx", text: $phone)
                        .keyboardType(.phonePad).foregroundStyle(Theme.onSurface)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))

                if !instances.isEmpty {
                    Text("الرقم المُرسِل").font(.callout.weight(.semibold)).foregroundStyle(Theme.onMuted)
                    ForEach(instances) { inst in
                        accountCard(inst)
                    }
                }

                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }

                Button { Task { await create() } } label: {
                    HStack {
                        if creating { ProgressView().tint(Theme.onPrimary) }
                        else { Text("بدء المحادثة").font(.headline) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.onPrimary)
                }
                .disabled(phone.isEmpty || creating)
            }
            .padding(20)
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task { await loadInstances() }
    }

    private func accountCard(_ inst: Instance) -> some View {
        let selected = inst.id == selectedId
        return Button { selectedId = inst.id } label: {
            HStack(spacing: 11) {
                Image(icon: .whatsapp).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AccountColor.color(inst.id), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(inst.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                    if let phone = inst.displayPhoneNumber { Text(phone).font(.caption).foregroundStyle(Theme.onMuted) }
                }
                Spacer()
                if selected { Image(icon: .check).foregroundStyle(Theme.primary) }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(selected ? Theme.primaryContainer : Theme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? Theme.primary : Theme.outline, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func loadInstances() async {
        do {
            let resp = try await Api.shared.instances()
            instances = resp.items
            selectedId = resp.defaultInstanceId ?? resp.items.first?.id
        } catch { }
    }

    private func create() async {
        creating = true; error = nil
        do {
            _ = try await Api.shared.createConversation(
                CreateConversationRequest(phone: phone.trimmingCharacters(in: .whitespaces), name: nil, instanceId: selectedId))
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        creating = false
    }
}
