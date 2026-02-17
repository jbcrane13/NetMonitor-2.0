//
//  ToolSheetContainer.swift
//  NetMonitor
//
//  Reusable container for tool sheet views that standardizes the
//  header (title + dismiss button), dividers, and layout structure.
//

import SwiftUI

/// A generic container that provides the standard tool sheet layout:
/// header with title and dismiss button, dividers between sections,
/// and a consistent frame.
///
/// For four-section tools (input + output + footer), provide all three
/// ViewBuilders. For three-section tools (content + footer), omit
/// `outputArea` using the convenience initializer.
struct ToolSheetContainer<InputArea: View, OutputArea: View, FooterContent: View, HeaderTrailing: View>: View {
    private let title: String
    private let iconName: String
    private let closeAccessibilityID: String
    private let minWidth: CGFloat
    private let minHeight: CGFloat
    private let headerTrailingContent: HeaderTrailing
    private let inputAreaContent: InputArea
    private let outputAreaContent: OutputArea
    private let footerAreaContent: FooterContent
    @Environment(\.dismiss) private var dismiss

    /// Full initializer with all four generic parameters.
    init(
        title: String,
        iconName: String,
        closeAccessibilityID: String,
        minWidth: CGFloat = 500,
        minHeight: CGFloat = 400,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder inputArea: () -> InputArea,
        @ViewBuilder outputArea: () -> OutputArea,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.title = title
        self.iconName = iconName
        self.closeAccessibilityID = closeAccessibilityID
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.headerTrailingContent = headerTrailing()
        self.inputAreaContent = inputArea()
        self.outputAreaContent = outputArea()
        self.footerAreaContent = footerContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            inputAreaContent

            if OutputArea.self != EmptyView.self {
                Divider()
                outputAreaContent
            }

            Divider()

            footerAreaContent
        }
        .frame(minWidth: minWidth, minHeight: minHeight)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(closeAccessibilityID)
            .padding(12)
        }
    }

    private var header: some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.headline)

            Spacer()

            headerTrailingContent
        }
        .padding()
    }
}

// MARK: - Four-section convenience (no header trailing)

extension ToolSheetContainer where HeaderTrailing == EmptyView {
    /// Four-section layout: header + inputArea + outputArea + footer.
    init(
        title: String,
        iconName: String,
        closeAccessibilityID: String,
        minWidth: CGFloat = 500,
        minHeight: CGFloat = 400,
        @ViewBuilder inputArea: () -> InputArea,
        @ViewBuilder outputArea: () -> OutputArea,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.init(
            title: title,
            iconName: iconName,
            closeAccessibilityID: closeAccessibilityID,
            minWidth: minWidth,
            minHeight: minHeight,
            headerTrailing: { EmptyView() },
            inputArea: inputArea,
            outputArea: outputArea,
            footerContent: footerContent
        )
    }
}

// MARK: - Three-section convenience (no output area, no header trailing)

extension ToolSheetContainer where OutputArea == EmptyView, HeaderTrailing == EmptyView {
    /// Three-section layout: header + inputArea + footer (no output area).
    init(
        title: String,
        iconName: String,
        closeAccessibilityID: String,
        minWidth: CGFloat = 500,
        minHeight: CGFloat = 400,
        @ViewBuilder inputArea: () -> InputArea,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.init(
            title: title,
            iconName: iconName,
            closeAccessibilityID: closeAccessibilityID,
            minWidth: minWidth,
            minHeight: minHeight,
            headerTrailing: { EmptyView() },
            inputArea: inputArea,
            outputArea: { EmptyView() },
            footerContent: footerContent
        )
    }
}

// MARK: - Three-section with header trailing content

extension ToolSheetContainer where OutputArea == EmptyView {
    /// Three-section layout with additional header trailing content.
    init(
        title: String,
        iconName: String,
        closeAccessibilityID: String,
        minWidth: CGFloat = 500,
        minHeight: CGFloat = 400,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder inputArea: () -> InputArea,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.init(
            title: title,
            iconName: iconName,
            closeAccessibilityID: closeAccessibilityID,
            minWidth: minWidth,
            minHeight: minHeight,
            headerTrailing: headerTrailing,
            inputArea: inputArea,
            outputArea: { EmptyView() },
            footerContent: footerContent
        )
    }
}
