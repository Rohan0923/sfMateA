import SwiftUI

/// sfMate's answers are light Markdown: paragraphs, **bold**, *italics*, bullet and numbered lists, ### headings,
/// --- dividers, links, and [1]-style citations (shown as small linked numbers, like on the website).
struct MessageText: View {
    let text: String
    let sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    inline(s)
                case .heading(let s):
                    inline(s).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.sfBrown).padding(.top, 2)
                case .bullet(let s, let level):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(Color.sfGold)
                        inline(s)
                    }
                    .padding(.leading, CGFloat(level) * 16 + 2)
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).").foregroundStyle(Color.sfMuted).monospacedDigit()
                        inline(s)
                    }
                    .padding(.leading, 2)
                case .divider:
                    Rectangle().fill(Color.sfBorder).frame(height: 1).padding(.vertical, 2)
                }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Color.sfText)
        .lineSpacing(3)
        .tint(.sfGoldDark)
        .textSelection(.enabled)
    }

    enum Block {
        case paragraph(String), heading(String), bullet(String, Int), numbered(String, String), divider
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix(while: { $0 == " " }).count
            if line.isEmpty { flush(); continue }
            if line.allSatisfy({ "-*_".contains($0) }) && line.count >= 3 { flush(); out.append(.divider); continue }
            if let m = line.firstMatch(of: /^#{1,6}\s+(.+)$/) { flush(); out.append(.heading(String(m.1))); continue }
            if let m = line.firstMatch(of: /^[-*•]\s+(.+)$/) { flush(); out.append(.bullet(String(m.1), indent >= 2 ? 1 : 0)); continue }
            if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.+)$/) { flush(); out.append(.numbered(String(m.1), String(m.2))); continue }
            paragraph.append(line)
        }
        flush()
        return out
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]

    /// [1] -> a superscript number, linked to the source's page when it has one.
    private func withCitations(_ s: String) -> String {
        let byN = Dictionary(sources.map { ($0.n, $0) }, uniquingKeysWith: { a, _ in a })
        return s.replacing(/\[(\d{1,2})\](?!\()/) { m in
            guard let n = Int(m.1), let source = byN[n] else { return String(m.0) }
            let mark = String(String(n).compactMap { Self.superscripts[$0] })
            return source.url.isEmpty ? mark : "[\(mark)](\(source.url))"
        }
    }

    private func inline(_ s: String) -> Text {
        let marked = withCitations(s)
        guard var attributed = try? AttributedString(markdown: marked, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return Text(marked) }
        let marks = Set(Self.superscripts.values)
        var i = attributed.startIndex
        while i < attributed.endIndex {   // citation numbers in the website's dark gold, bold
            let next = attributed.characters.index(after: i)
            if marks.contains(attributed.characters[i]) {
                attributed[i..<next].foregroundColor = .sfGoldDark
                attributed[i..<next].inlinePresentationIntent = .stronglyEmphasized
            }
            i = next
        }
        return Text(attributed)
    }
}

/// "Sources (n)", tucked away under an answer; each page once, with every citation number pointing to it.
struct SourcesView: View {
    let sources: [Source]
    @State private var open = false

    private var pages: [(title: String, url: String, nums: [Int])] {
        var order: [String] = []
        var byTitle: [String: (url: String, nums: [Int])] = [:]
        for s in sources {
            if byTitle[s.title] == nil { order.append(s.title); byTitle[s.title] = (s.url, []) }
            byTitle[s.title]?.nums.append(s.n)
        }
        return order.map { ($0, byTitle[$0]!.url, byTitle[$0]!.nums) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Color.sfBorder).frame(height: 1).padding(.top, 4)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("Sources (\(pages.count))")
                }
                .font(.system(size: 13)).foregroundStyle(Color.sfMuted)
            }
            .buttonStyle(.plain)
            if open {
                ForEach(pages, id: \.title) { page in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("[\(page.nums.map(String.init).joined(separator: ", "))]").foregroundStyle(Color.sfMuted)
                        if let url = URL(string: page.url), !page.url.isEmpty {
                            Link(page.title, destination: url).foregroundStyle(Color.sfGoldDark)
                        } else {
                            Text(page.title).foregroundStyle(Color.sfText)
                        }
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }
}
