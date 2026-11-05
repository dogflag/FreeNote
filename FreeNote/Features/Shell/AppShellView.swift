import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var section: AppSection = .notes
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760 || horizontalSizeClass == .compact

            Group {
                if compact {
                    VStack(spacing: 0) {
                        moduleContent
                        compactNavigation
                    }
                } else {
                    HStack(spacing: 0) {
                        sidebar
                        Rectangle()
                            .fill(FNTheme.divider)
                            .frame(width: 1)
                        moduleContent
                    }
                }
            }
            .background(FNTheme.appBackground)
            .ignoresSafeArea(edges: compact ? Edge.Set.bottom : Edge.Set())
        }
        .preferredColorScheme(store.settings.appearance.fnColorScheme)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch section {
        case .notes:
            NotesWorkspaceView()
        case .bookshelf:
            BookshelfView()
        case .library:
            LibraryView()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            Button {
                section = .notes
            } label: {
                VStack(spacing: 5) {
                    Text("F")
                        .font(FNTheme.serif(27, weight: .semibold))
                        .foregroundStyle(FNTheme.selectionText)
                        .frame(width: 42, height: 42)
                        .background(FNTheme.selectionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("FreeNote")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.bottom, 18)

            ForEach(AppSection.allCases, id: \.self) { item in
                SidebarDestinationButton(
                    section: item,
                    isSelected: section == item
                ) {
                    section = item
                }
            }

            Spacer()

            FNIconButton(symbol: "gearshape", tint: FNTheme.secondaryInk, size: 42) {
                showingSettings = true
            }
            .padding(.bottom, 18)
        }
        .frame(width: 92)
        .frame(maxHeight: .infinity)
        .background(FNTheme.sidebar)
    }

    private var compactNavigation: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases, id: \.self) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.fnSymbol)
                            .font(.system(size: 17, weight: .medium))
                        Text(item.fnTitle)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(section == item ? FNTheme.accent : FNTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .background(FNTheme.sidebar)
        .overlay(alignment: .top) {
            Rectangle().fill(FNTheme.divider).frame(height: 1)
        }
    }
}

private struct SidebarDestinationButton: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: section.fnSymbol)
                    .font(.system(size: 19, weight: .medium))
                Text(section.fnTitle)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isSelected ? FNTheme.accent : FNTheme.secondaryInk)
            .frame(width: 58, height: 58)
            .background(isSelected ? FNTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.fnTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }
}
