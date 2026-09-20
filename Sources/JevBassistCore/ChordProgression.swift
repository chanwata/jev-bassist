import Foundation

public enum ChordProgressionError: Error, CustomStringConvertible, Equatable {
    case empty
    case invalidSymbol(String)

    public var description: String {
        switch self {
        case .empty:
            return "Chord progression must contain at least one chord."
        case let .invalidSymbol(symbol):
            return "Unsupported chord symbol '\(symbol)'. Try forms such as C, Dm7, G7, F#dim, or Bbmaj7."
        }
    }
}

public enum ChordProgressionParser {
    public static func parse(_ value: String) throws -> [ChordCandidate] {
        let symbols = value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !symbols.isEmpty, symbols.allSatisfy({ !$0.isEmpty }) else {
            throw ChordProgressionError.empty
        }
        return try symbols.map(parseSymbol)
    }

    private static func parseSymbol(_ symbol: String) throws -> ChordCandidate {
        let characters = Array(symbol)
        guard let first = characters.first else {
            throw ChordProgressionError.invalidSymbol(symbol)
        }
        let naturalRoots: [Character: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]
        let rootLetter = Character(String(first).uppercased())
        guard var root = naturalRoots[rootLetter] else {
            throw ChordProgressionError.invalidSymbol(symbol)
        }

        var suffixStart = 1
        if characters.count > 1 {
            switch characters[1] {
            case "#", "♯":
                root += 1
                suffixStart = 2
            case "b", "♭":
                root -= 1
                suffixStart = 2
            default:
                break
            }
        }
        let rawSuffix = String(characters.dropFirst(suffixStart))
        let suffix = rawSuffix.lowercased()
        let quality: ChordQuality
        if rawSuffix == "M" || rawSuffix == "M7" {
            quality = .major
        } else {
            switch suffix {
            case "", "maj", "major", "7", "maj7", "major7":
                quality = .major
            case "m", "min", "minor", "m7", "min7", "minor7":
                quality = .minor
            case "dim", "dim7", "°", "°7", "o", "o7":
                quality = .diminished
            default:
                throw ChordProgressionError.invalidSymbol(symbol)
            }
        }
        return ChordCandidate(
            rootPitchClass: UInt8((root % 12 + 12) % 12),
            quality: quality,
            confidence: 1
        )
    }
}
