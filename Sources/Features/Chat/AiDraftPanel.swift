import SwiftUI

// Suggestion panel for the LIS smart reply, shown directly above the
// composer. Renders exactly three draft states — pending (light hint),
// ready (text + actions), failed (server's Arabic error) — and nothing for
// any other status.
//
// Invariants (see AiDraft in Models.swift): nothing is auto-sent, and the
// text reaches the composer only through the Edit button. Buttons follow
// the app-wide gating pattern: hidden without the permission, never
// disabled. The direct-send button is additionally hidden while the text
// still contains anonymization placeholders — those must be replaced by
// hand via Edit before anything goes to the patient.
struct AiDraftPanel: View {
    @ObservedObject var vm: ChatViewModel

    @State private var showRegeneratePrompt = false
    @State private var instruction = ""

    var body: some View {
        if vm.canViewDrafts, let draft = vm.draft, draft.isDisplayable {
            content(draft)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .background(Theme.background)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .alert(L("ما التعديل المطلوب؟"), isPresented: $showRegeneratePrompt) {
                    TextField(L("مثال: خليها أقصر"), text: $instruction)
                    Button(L("إجابة جديدة")) {
                        let text = instruction
                        instruction = ""
                        Task { await vm.regenerateDraft(instruction: text) }
                    }
                    Button(L("إلغاء"), role: .cancel) { instruction = "" }
                }
        }
    }

    @ViewBuilder
    private func content(_ draft: AiDraft) -> some View {
        if draft.isPending {
            pendingRow
        } else if draft.isFailed {
            failedRow(draft)
        } else if draft.isReady {
            readyCard(draft)
        }
    }

    private var pendingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text(L("جاري تحضير رد مقترح…"))
                .font(.wx(12)).foregroundStyle(Theme.onMuted)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassCard(16)
    }

    private func failedRow(_ draft: AiDraft) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.wx(14)).foregroundStyle(Theme.warning)
            // The server sends display-ready Arabic failure text.
            Text(draft.error?.isEmpty == false ? draft.error! : L("تعذّر تحضير الرد المقترح"))
                .font(.wx(12)).foregroundStyle(Theme.onMuted)
                .lineLimit(2)
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassCard(16)
    }

    private func readyCard(_ draft: AiDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.wx(13)).foregroundStyle(Theme.primary)
                Text(L("رد مقترح"))
                    .font(.wx(12, .bold)).foregroundStyle(Theme.primary)
                if !draft.sources.isEmpty {
                    Text(draft.sources.joined(separator: " · "))
                        .font(.wx(10)).foregroundStyle(Theme.onFaint)
                        .lineLimit(1)
                }
                Spacer()
                dismissButton
            }

            if draft.escalate {
                escalateBanner(draft)
            }

            highlightedText(draft.draftText ?? "")
                .font(.wx(14)).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionsRow(draft)
        }
        .padding(12)
        .glassCard(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(draft.escalate ? Theme.danger.opacity(0.55) : .clear, lineWidth: 1)
        )
    }

    private func escalateBanner(_ draft: AiDraft) -> some View {
        // The draft is an apology + handover, not a normal answer — say so.
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.wx(12)).foregroundStyle(Theme.danger)
            Text(L("مريض مستاء — يحتاج متابعة"))
                .font(.wx(12, .semibold)).foregroundStyle(Theme.danger)
            if draft.escalateReason == "threat" {
                Text(L("تهديد"))
                    .font(.wx(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Theme.danger, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func actionsRow(_ draft: AiDraft) -> some View {
        let hasPlaceholders = AiDraftPlaceholders.contains(draft.draftText ?? "")
        HStack(spacing: 8) {
            if vm.canUseDrafts {
                if hasPlaceholders {
                    // {PATIENT_NAME}-style tokens must never reach the
                    // patient verbatim — force the Edit path.
                    Text(L("استبدل الرموز النائبة يدوياً — اضغط «تعديل»"))
                        .font(.wx(10.5)).foregroundStyle(Theme.warning)
                        .lineLimit(2)
                } else {
                    actionButton(L("إرسال"), icon: "paperplane.fill", prominent: true) {
                        Task { await vm.sendDraftAsIs() }
                    }
                    .disabled(vm.sending)
                }
                actionButton(L("تعديل"), icon: "pencil") { vm.editDraft() }
            }
            if vm.canRegenerateDrafts {
                actionButton(L("إجابة جديدة"), icon: "arrow.clockwise") {
                    showRegeneratePrompt = true
                }
            }
            Spacer()
        }
    }

    private func actionButton(_ title: String, icon: String, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.wx(11, .semibold))
                Text(title).font(.wx(12, .semibold))
            }
            .foregroundStyle(prominent ? Theme.onPrimary : Theme.onSurface)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(prominent ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.surface2), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dismissButton: some View {
        Button { Task { await vm.dismissDraft() } } label: {
            Image(systemName: "xmark")
                .font(.wx(11, .semibold)).foregroundStyle(Theme.onMuted)
                .frame(width: 26, height: 26)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("إخفاء"))
    }

    /// Draft text with the anonymization placeholders rendered in a warning
    /// tint so the operator spots what needs replacing. Displayed verbatim —
    /// never auto-filled (one phone number can belong to several patients).
    private func highlightedText(_ text: String) -> Text {
        AiDraftPlaceholders.segments(of: text).reduce(Text("")) { acc, seg in
            acc + (seg.isPlaceholder
                   ? Text(seg.text).foregroundColor(Theme.warning).fontWeight(.bold)
                   : Text(seg.text))
        }
    }
}
