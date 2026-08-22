import SwiftUI

// WhatsX 2.0 quick-replies bar (design 4c/4n): ONE horizontal chips row
// above the composer. The first chip is the LIS suggested reply (amber
// family); the rest are the team's ready replies (white glass). Tapping the
// AI chip expands the suggestion card; tapping a ready chip FILLS the
// composer — chips never send anything on their own.
//
// Every AI-draft invariant survives the redesign:
//  - nothing is ever auto-sent;
//  - draft text enters the composer only through the explicit Edit action
//    (feeding the server's sent_as_is/edited/ignored training signal);
//  - the DIRECT send button stays in the expanded card BY OWNER DECISION
//    (it preserves the sent_as_is classification) and hides while
//    anonymization placeholders remain — those are replaced by hand;
//  - buttons follow hide-don't-disable permission gating (aiDrafts.*).
struct QuickReplyBar: View {
    @ObservedObject var vm: ChatViewModel

    @State private var draftExpanded = false
    @State private var showRegeneratePrompt = false
    @State private var instruction = ""

    private var hasDraft: Bool {
        vm.canViewDrafts && vm.draft?.isDisplayable == true
    }

    var body: some View {
        if hasDraft || !vm.readyReplies.isEmpty {
            VStack(spacing: 6) {
                if draftExpanded, let draft = vm.draft, draft.isReady {
                    expandedCard(draft)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                chipsRow
            }
            .padding(.top, 6)
            .alert(L("ما التعديل المطلوب؟"), isPresented: $showRegeneratePrompt) {
                TextField(L("مثال: خليها أقصر"), text: $instruction)
                Button(L("إجابة جديدة")) {
                    let text = instruction
                    instruction = ""
                    Task { await vm.regenerateDraft(instruction: text) }
                }
                Button(L("إلغاء"), role: .cancel) { instruction = "" }
            }
            .onChange(of: vm.draft) { newValue in
                // The draft resolved (sent/expired/colleague acted) — fold
                // the card away instead of showing a stale suggestion.
                if newValue?.isReady != true { draftExpanded = false }
            }
        }
    }

    // MARK: - Chips row

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasDraft, let draft = vm.draft {
                    aiChip(draft)
                }
                ForEach(vm.readyReplies) { reply in
                    readyChip(reply)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private func aiChip(_ draft: AiDraft) -> some View {
        if draft.isPending {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(L("جاري تحضير رد مقترح…")).font(.wx(12))
            }
            .foregroundStyle(Theme.draftChipText)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Theme.draftChipBg, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.draftChipBorder, lineWidth: 1))
        } else if draft.isFailed {
            Button { Task { await vm.dismissDraft() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle").font(.wx(12))
                    Text(draft.error?.isEmpty == false ? draft.error! : L("تعذّر تحضير الرد المقترح"))
                        .font(.wx(12)).lineLimit(1)
                    Image(systemName: "xmark").font(.wx(10, .semibold))
                }
                .foregroundStyle(Theme.onMuted)
                .padding(.horizontal, 12).frame(height: 34)
                .glassCapsule()
            }
            .buttonStyle(.plain)
        } else if draft.isReady {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    draftExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.wx(12, .semibold))
                    Text(draft.draftText ?? "").font(.wx(12.5, .semibold))
                        .lineLimit(1).frame(maxWidth: 190, alignment: .leading)
                    Image(systemName: draftExpanded ? "chevron.down" : "chevron.up")
                        .font(.wx(10, .semibold))
                }
                .foregroundStyle(Theme.draftChipText)
                .padding(.horizontal, 12).frame(height: 34)
                .background(Theme.draftChipBg, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.draftChipBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("رد مقترح"))
        }
    }

    private func readyChip(_ reply: ReadyMessage) -> some View {
        Button {
            Haptics.tap()
            // Fills the composer only — the operator reviews, then sends.
            vm.insertReady(reply.body)
        } label: {
            Text(reply.name.isEmpty ? reply.body : reply.name)
                .font(.wx(12.5, .medium))
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1).frame(maxWidth: 160)
                .padding(.horizontal, 12).frame(height: 34)
                .glassCapsule()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded suggestion card (design 4n)

    private func expandedCard(_ draft: AiDraft) -> some View {
        let hasPlaceholders = AiDraftPlaceholders.contains(draft.draftText ?? "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.wx(13)).foregroundStyle(Theme.draftChipText)
                Text(L("رد مقترح"))
                    .font(.wx(12, .bold)).foregroundStyle(Theme.draftChipText)
                if !draft.sources.isEmpty {
                    Text(draft.sources.joined(separator: " · "))
                        .font(.wx(10)).foregroundStyle(Theme.onFaint).lineLimit(1)
                }
                Spacer()
                Button { Task { await vm.dismissDraft() } } label: {
                    Image(systemName: "xmark")
                        .font(.wx(11, .semibold)).foregroundStyle(Theme.onMuted)
                        .frame(width: 26, height: 26)
                        .background(Theme.surface2.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("إخفاء"))
            }

            if draft.escalate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.wx(11)).foregroundStyle(Theme.danger)
                    Text(L("مريض مستاء — يحتاج متابعة"))
                        .font(.wx(11.5, .semibold)).foregroundStyle(Theme.danger)
                    Spacer()
                }
            }

            highlightedText(draft.draftText ?? "")
                .font(.wx(14)).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasPlaceholders {
                Text(L("استبدل الرموز النائبة يدوياً — اضغط «تعديل»"))
                    .font(.wx(10.5)).foregroundStyle(Theme.warning)
            }

            HStack(spacing: 8) {
                if vm.canUseDrafts {
                    if !hasPlaceholders {
                        cardButton(L("إرسال"), icon: "paperplane.fill", prominent: true) {
                            Task { await vm.sendDraftAsIs() }
                        }
                        .disabled(vm.sending)
                    }
                    cardButton(L("تعديل"), icon: "pencil") {
                        vm.editDraft()
                        withAnimation { draftExpanded = false }
                    }
                }
                if vm.canRegenerateDrafts {
                    cardButton(L("إجابة جديدة"), icon: "arrow.clockwise") {
                        showRegeneratePrompt = true
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Theme.draftCardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(draft.escalate ? Theme.danger.opacity(0.55) : Theme.draftChipBorder, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func cardButton(_ title: String, icon: String, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.wx(11, .semibold))
                Text(title).font(.wx(12, .semibold))
            }
            .foregroundStyle(prominent ? .white : Theme.onSurface)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(prominent ? AnyShapeStyle(Theme.amberAction) : AnyShapeStyle(Theme.surface2.opacity(0.8)), in: Capsule())
        }
        .buttonStyle(.plain)
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
