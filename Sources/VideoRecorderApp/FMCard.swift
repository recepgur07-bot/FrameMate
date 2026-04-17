import SwiftUI

/// Reusable card container used in the FrameMate content zone.
/// When `isCollapsible` is true a chevron appears and tapping the header
/// toggles the card between expanded and collapsed states.
/// Cards always start expanded; state is NOT persisted between launches.
struct FMCard<Content: View>: View {
    let icon: String
    let title: String
    var isCollapsible: Bool = false
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCollapsible {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    headerRow
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(
                    isExpanded
                        ? String(localized: "Daraltmak için dokun")
                        : String(localized: "Genişletmek için dokun")
                )
            } else {
                headerRow
                    .accessibilityHidden(true)
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(16)
                .accessibilityElement(children: .contain)
            }
        }
        .accessibilityElement(children: .contain)
        .background(Color.fmCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Shadow only — no stroke border (preview card has its own border)
        .shadow(color: Color.primary.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.fmAccent)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            if isCollapsible {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 0 : -180))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}
