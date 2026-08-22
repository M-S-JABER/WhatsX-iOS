import SwiftUI

struct NewConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var instances: [Instance] = []
    @State private var selectedId: String?
    @State private var loadingInstances = true
    @State private var instancesError: String?
    @State private var creating = false
    @State private var error: String?
    @FocusState private var phoneFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("محادثة جديدة")).font(.wx(20, .bold)).foregroundStyle(Theme.onSurface)

                // WhatsX 2.0 field recipe (design 4j): r12 surface with a
                // 1.5px border that warms to amber while focused.
                HStack(spacing: 10) {
                    Image(icon: .call).foregroundStyle(Theme.onFaint)
                    TextField("+9647xxxxxxxxx", text: $phone)
                        .keyboardType(.phonePad).foregroundStyle(Theme.onSurface)
                        .focused($phoneFocused)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(phoneFocused ? Theme.primary : Theme.outline, lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: phoneFocused)

                if !instances.isEmpty {
                    Text(L("الرقم المُرسِل")).font(.wx(16, .semibold)).foregroundStyle(Theme.onMuted)
                    ForEach(instances) { inst in
                        accountCard(inst)
                    }
                } else if loadingInstances {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.primary)
                        Text(L("جارٍ تحميل الأرقام المُرسِلة…")).font(.wx(13)).foregroundStyle(Theme.onMuted)
                    }
                } else if let instancesError {
                    HStack(spacing: 8) {
                        Text(instancesError).font(.wx(13)).foregroundStyle(Theme.danger)
                        Spacer()
                        Button(L("إعادة المحاولة")) { Task { await loadInstances() } }
                            .font(.wx(13, .semibold)).foregroundStyle(Theme.primary)
                    }
                }

                if let error { Text(error).font(.wx(13)).foregroundStyle(Theme.danger) }

                Button {
                    Haptics.action()
                    Task { await create() }
                } label: {
                    HStack {
                        if creating { ProgressView().tint(.white) }
                        else { Text(L("بدء المحادثة")).font(.wx(17, .semibold)) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.amberAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.amberShadow, radius: 10, y: 4)
                }
                .buttonStyle(.pressable)
                .disabled(phone.isEmpty || creating || (!instances.isEmpty && selectedId == nil))
                .opacity(phone.isEmpty ? 0.6 : 1)
            }
            .padding(20)
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                    Text(inst.label).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                    if let phone = inst.displayPhoneNumber { Text(phone).font(.wx(12)).foregroundStyle(Theme.onMuted) }
                }
                Spacer()
                if selected { Image(icon: .check).foregroundStyle(Theme.primary) }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(selected ? Theme.primarySoft : Theme.surface1, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? Theme.primary : Theme.outline, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func loadInstances() async {
        loadingInstances = true
        do {
            let resp = try await Api.shared.instances()
            instances = resp.items
            selectedId = resp.defaultInstanceId ?? resp.items.first?.id
            instancesError = nil
        } catch { instancesError = error.apiMessage }
        loadingInstances = false
    }

    private func create() async {
        creating = true; error = nil
        do {
            let resp = try await Api.shared.createConversation(
                CreateConversationRequest(phone: phone.trimmingCharacters(in: .whitespaces), displayName: nil, instanceId: selectedId))
            dismiss()
            // Land the operator straight in the new thread (design 4j) —
            // same deep-link path a tapped notification takes.
            if let conv = resp.conversation {
                InboxBus.shared.requestOpenConversation(conv.id)
            }
        } catch {
            self.error = error.apiMessage
        }
        creating = false
    }
}
