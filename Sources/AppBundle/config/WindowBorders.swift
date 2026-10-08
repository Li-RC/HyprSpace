import AppKit
import Common

struct WindowBorders: ConvenienceMutable {
    var enabled = false
    var width = 2
    var activeColor = BorderColor(rgb: 0x89b4fa)
    var inactiveColor = BorderColor(rgb: 0x45475a)
}

struct BorderColor: Equatable {
    let rgb: UInt32

    init(rgb: UInt32) { self.rgb = rgb }
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.rgb = rgb
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

private let windowBordersParserTable: [String: any ParserProtocol<WindowBorders>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, { raw, trace in
        parseInt(raw, trace).flatMap { value in
            (1 ... 8).contains(value) ? .success(value) : .failure(.init(trace, "Border width must be between 1 and 8"))
        }
    }),
    "active-color": Parser(\.activeColor, parseBorderColor),
    "inactive-color": Parser(\.inactiveColor, parseBorderColor),
]

private func parseBorderColor(_ raw: OrderedJson, _ trace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<BorderColor> {
    parseString(raw, trace).flatMap { BorderColor(hex: $0).toResult(.init(trace, "Expected a #RRGGBB color")) }
}

func parseWindowBorders(_ raw: OrderedJson, _ trace: ConfigBacktrace, _ context: inout ConfigParserContext) -> WindowBorders {
    parseTable(raw, WindowBorders(), windowBordersParserTable, trace, &context)
}
