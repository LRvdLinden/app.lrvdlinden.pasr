import Foundation

/// A 1D barcode as a row of modules (true = bar), without quiet zones.
struct LinearBarcode: Equatable {
    var modules: [Bool]
    /// The text printed under the bars, if it differs from the input (e.g. an added check digit).
    var humanReadable: String
}

enum BarcodeEncodingError: Error, Equatable {
    case invalidCharacters
    case invalidLength
}

/// Pure-Swift encoders for the 1D formats Core Image cannot draw (and for watchOS, which has no Core Image).
enum BarcodeEncoder {

    static func encode(_ value: String, as format: BarcodeFormat) throws -> LinearBarcode {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .ean13: return try ean13(input)
        case .ean8: return try ean8(input)
        case .upcA: return try upcA(input)
        case .code39: return try code39(input)
        case .itf: return try itf(input)
        case .code128: return try code128(input)
        case .qr, .pdf417, .aztec: throw BarcodeEncodingError.invalidCharacters
        }
    }

    // MARK: - EAN / UPC

    /// GS1 check digit for a string of digits that does not yet contain one.
    static func gs1CheckDigit(_ digits: String) -> Int {
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            let digit = Int(String(char)) ?? 0
            sum += index % 2 == 0 ? digit * 3 : digit
        }
        return (10 - sum % 10) % 10
    }

    static func ean13(_ input: String) throws -> LinearBarcode {
        guard input.allSatisfy(\.isASCIIDigit) else { throw BarcodeEncodingError.invalidCharacters }
        var digits = input
        switch digits.count {
        case 12: digits += String(gs1CheckDigit(digits))
        case 13: break
        default: throw BarcodeEncodingError.invalidLength
        }
        let values = digits.map { Int(String($0))! }
        let parity = Array(BarcodeTables.eanParity[values[0]])
        var bits = "101"
        for i in 1...6 {
            bits += parity[i - 1] == "A" ? BarcodeTables.eanL[values[i]] : BarcodeTables.eanG[values[i]]
        }
        bits += "01010"
        for i in 7...12 { bits += BarcodeTables.eanR[values[i]] }
        bits += "101"
        return LinearBarcode(modules: modules(bits), humanReadable: digits)
    }

    static func ean8(_ input: String) throws -> LinearBarcode {
        guard input.allSatisfy(\.isASCIIDigit) else { throw BarcodeEncodingError.invalidCharacters }
        var digits = input
        switch digits.count {
        case 7: digits += String(gs1CheckDigit(digits))
        case 8: break
        default: throw BarcodeEncodingError.invalidLength
        }
        let values = digits.map { Int(String($0))! }
        var bits = "101"
        for i in 0...3 { bits += BarcodeTables.eanL[values[i]] }
        bits += "01010"
        for i in 4...7 { bits += BarcodeTables.eanR[values[i]] }
        bits += "101"
        return LinearBarcode(modules: modules(bits), humanReadable: digits)
    }

    /// UPC-A is an EAN-13 whose first digit is 0.
    static func upcA(_ input: String) throws -> LinearBarcode {
        guard input.allSatisfy(\.isASCIIDigit) else { throw BarcodeEncodingError.invalidCharacters }
        guard input.count == 11 || input.count == 12 else { throw BarcodeEncodingError.invalidLength }
        let ean = try ean13("0" + input)
        return LinearBarcode(modules: ean.modules, humanReadable: String(ean.humanReadable.dropFirst()))
    }

    // MARK: - Code 39

    static func code39(_ input: String) throws -> LinearBarcode {
        let text = input.uppercased()
        guard !text.isEmpty else { throw BarcodeEncodingError.invalidLength }
        var bits = BarcodeTables.code39StartStop + "0"
        for char in text {
            guard let index = BarcodeTables.code39Characters.firstIndex(of: char) else {
                throw BarcodeEncodingError.invalidCharacters
            }
            bits += BarcodeTables.code39[index] + "0"
        }
        bits += BarcodeTables.code39StartStop
        return LinearBarcode(modules: modules(bits), humanReadable: text)
    }

    // MARK: - Interleaved 2 of 5

    static func itf(_ input: String) throws -> LinearBarcode {
        guard !input.isEmpty, input.allSatisfy(\.isASCIIDigit) else { throw BarcodeEncodingError.invalidCharacters }
        let digits = input.count % 2 == 0 ? input : "0" + input
        let values = digits.map { Int(String($0))! }
        let narrow = 1, wide = 3
        var bits = "1010" // start: narrow bar, narrow space, narrow bar, narrow space
        var i = 0
        while i < values.count {
            let bars = Array(BarcodeTables.itf[values[i]])
            let spaces = Array(BarcodeTables.itf[values[i + 1]])
            for k in 0..<5 {
                bits += String(repeating: "1", count: bars[k] == "1" ? wide : narrow)
                bits += String(repeating: "0", count: spaces[k] == "1" ? wide : narrow)
            }
            i += 2
        }
        bits += String(repeating: "1", count: wide) + "0" + "1" // stop: wide bar, narrow space, narrow bar
        return LinearBarcode(modules: modules(bits), humanReadable: digits)
    }

    // MARK: - Code 128 (subsets B and C, switching for runs of digits)

    static func code128(_ input: String) throws -> LinearBarcode {
        let chars = Array(input)
        guard !chars.isEmpty else { throw BarcodeEncodingError.invalidLength }
        guard chars.allSatisfy({ $0.isASCII && ($0.asciiValue! >= 32 && $0.asciiValue! <= 126) }) else {
            throw BarcodeEncodingError.invalidCharacters
        }

        func digitRun(from start: Int) -> Int {
            var end = start
            while end < chars.count, chars[end].isASCIIDigit { end += 1 }
            return end - start
        }

        var codes: [Int] = []
        var subset: Character = " "
        var i = 0
        while i < chars.count {
            let run = digitRun(from: i)
            let atStart = i == 0
            let atEnd = i + run == chars.count
            // Subset C pays off for 4+ digits at the start or end, or 6+ in the middle.
            let useC = run >= ((atStart || atEnd) ? 4 : 6) || (atStart && atEnd && run >= 2 && run % 2 == 0)
            if useC {
                let pairs = run / 2
                // With an odd run, the leftover digit goes first in subset B, unless the run is at the start.
                if run % 2 == 1 && !atStart {
                    if subset != "B" { codes.append(subset == " " ? 104 : 100); subset = "B" }
                    codes.append(Int(chars[i].asciiValue!) - 32)
                    i += 1
                }
                if subset != "C" { codes.append(subset == " " ? 105 : 99); subset = "C" }
                for _ in 0..<pairs {
                    codes.append(Int(String(chars[i]))! * 10 + Int(String(chars[i + 1]))!)
                    i += 2
                }
            } else {
                if subset != "B" { codes.append(subset == " " ? 104 : 100); subset = "B" }
                codes.append(Int(chars[i].asciiValue!) - 32)
                i += 1
            }
        }

        var checksum = codes[0]
        for (position, code) in codes.enumerated().dropFirst() { checksum += position * code }
        codes.append(checksum % 103)

        var bits = codes.map { BarcodeTables.code128[$0] }.joined()
        bits += BarcodeTables.code128Stop
        return LinearBarcode(modules: modules(bits), humanReadable: input)
    }

    // MARK: - Helpers

    private static func modules(_ bits: String) -> [Bool] { bits.map { $0 == "1" } }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
