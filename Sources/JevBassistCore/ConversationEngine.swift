import Foundation

public enum ConversationRelationship: String, Codable, Equatable, Sendable {
    case rest
    case echo
    case tailVariation
    case hold
    case sequence
    case inversion
    case fragmentation
    case augmentation
    case originalReturn
}

public struct ConversationLineage: Codable, Equatable, Sendable {
    public let originMotifID: UInt64
    public let sourceMotifID: UInt64
    public let responseID: UInt64
    public let parentResponseID: UInt64?
    public let generation: Int
    public let relationship: ConversationRelationship
    public let originGesture: [ConversationGesturePoint]
    public let sourceGesture: [ConversationGesturePoint]
    public let responseGesture: [ConversationGesturePoint]

    public init(
        originMotifID: UInt64,
        sourceMotifID: UInt64,
        responseID: UInt64,
        parentResponseID: UInt64?,
        generation: Int,
        relationship: ConversationRelationship,
        originGesture: [ConversationGesturePoint] = [],
        sourceGesture: [ConversationGesturePoint] = [],
        responseGesture: [ConversationGesturePoint] = []
    ) {
        self.originMotifID = originMotifID
        self.sourceMotifID = sourceMotifID
        self.responseID = responseID
        self.parentResponseID = parentResponseID
        self.generation = generation
        self.relationship = relationship
        self.originGesture = originGesture
        self.sourceGesture = sourceGesture
        self.responseGesture = responseGesture
    }

    private enum CodingKeys: String, CodingKey {
        case originMotifID, sourceMotifID, responseID, parentResponseID
        case generation, relationship, originGesture, sourceGesture, responseGesture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            originMotifID: try container.decode(UInt64.self, forKey: .originMotifID),
            sourceMotifID: try container.decode(UInt64.self, forKey: .sourceMotifID),
            responseID: try container.decode(UInt64.self, forKey: .responseID),
            parentResponseID: try container.decodeIfPresent(UInt64.self, forKey: .parentResponseID),
            generation: try container.decode(Int.self, forKey: .generation),
            relationship: try container.decode(ConversationRelationship.self, forKey: .relationship),
            originGesture: try container.decodeIfPresent(
                [ConversationGesturePoint].self,
                forKey: .originGesture
            ) ?? [],
            sourceGesture: try container.decodeIfPresent(
                [ConversationGesturePoint].self,
                forKey: .sourceGesture
            ) ?? [],
            responseGesture: try container.decodeIfPresent(
                [ConversationGesturePoint].self,
                forKey: .responseGesture
            ) ?? []
        )
    }
}

public struct ConversationGesturePoint: Codable, Equatable, Sendable {
    public let note: UInt8
    public let relativeOnsetBeats: Double
    public let durationBeats: Double
    public let intensity: Double

    public init(
        note: UInt8,
        relativeOnsetBeats: Double,
        durationBeats: Double,
        intensity: Double
    ) {
        self.note = note
        self.relativeOnsetBeats = relativeOnsetBeats
        self.durationBeats = durationBeats
        self.intensity = min(1, max(0, intensity))
    }
}

public struct ConversationResponseNote: Codable, Equatable, Sendable {
    public let note: UInt8
    public let velocity: UInt8
    public let relativeOnsetBeats: Double
    public let durationBeats: Double

    public init(
        note: UInt8,
        velocity: UInt8,
        relativeOnsetBeats: Double,
        durationBeats: Double
    ) {
        self.note = note
        self.velocity = velocity
        self.relativeOnsetBeats = relativeOnsetBeats
        self.durationBeats = durationBeats
    }
}

public struct ConversationScore: Codable, Equatable, Sendable {
    public let recognition: Double
    public let space: Double
    public let voiceLeading: Double
    public let modalFit: Double
    public let contourIntegrity: Double
    public let cadence: Double
    public let continuity: Double

    public var total: Double {
        recognition * 0.28
            + space * 0.1
            + voiceLeading * 0.18
            + modalFit * 0.1
            + contourIntegrity * 0.14
            + cadence * 0.1
            + continuity * 0.1
    }

    public init(
        recognition: Double,
        space: Double,
        voiceLeading: Double,
        modalFit: Double,
        contourIntegrity: Double = 0.5,
        cadence: Double = 0.5,
        continuity: Double = 0.5
    ) {
        self.recognition = min(1, max(0, recognition))
        self.space = min(1, max(0, space))
        self.voiceLeading = min(1, max(0, voiceLeading))
        self.modalFit = min(1, max(0, modalFit))
        self.contourIntegrity = min(1, max(0, contourIntegrity))
        self.cadence = min(1, max(0, cadence))
        self.continuity = min(1, max(0, continuity))
    }
}

public struct ConversationResponseCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let relationship: ConversationRelationship
    public let notes: [ConversationResponseNote]
    public let score: ConversationScore

    public init(
        id: String,
        relationship: ConversationRelationship,
        notes: [ConversationResponseNote],
        score: ConversationScore
    ) {
        self.id = id
        self.relationship = relationship
        self.notes = notes
        self.score = score
    }
}

public struct ModalPitchContext: Equatable, Sendable {
    public let mode: MusicalMode
    public let tonalCenterPitchClass: UInt8
    public let companionRange: ClosedRange<Int>

    public init(
        mode: MusicalMode,
        tonalCenterPitchClass: UInt8,
        companionRange: ClosedRange<Int> = 43...67
    ) {
        self.mode = mode
        self.tonalCenterPitchClass = tonalCenterPitchClass % 12
        self.companionRange = companionRange
    }

    public func contains(_ note: UInt8) -> Bool {
        let relative = (Int(note % 12) - Int(tonalCenterPitchClass) + 12) % 12
        return mode.intervals.contains(relative)
    }

    public func conservativeProjection(_ note: UInt8) -> UInt8 {
        let folded = fold(Int(note), into: 55...79)
        return UInt8(nearestModalPitch(to: folded, within: 55...79))
    }

    public func neighboringScaleTone(from note: UInt8, direction: Int) -> UInt8 {
        let coordinate = scaleDegree(for: Int(note)) + (direction >= 0 ? 1 : -1)
        return UInt8(max(0, min(127, pitch(forScaleDegree: coordinate))))
    }

    /// Projects pitch classes first, then chooses one octave displacement for
    /// the whole phrase. This keeps a rising line rising at register edges.
    public func placePhrase(
        _ pitches: [UInt8],
        continuityReference: UInt8? = nil
    ) -> [UInt8] {
        guard !pitches.isEmpty else { return [] }
        let modal = modalizePhrase(pitches.map(Int.init))
        let rangeCenter = Double(companionRange.lowerBound + companionRange.upperBound) / 2
        let shifts = stride(from: -48, through: 48, by: 12)
        let shift = shifts.min { left, right in
            placementCost(modal, shift: left, center: rangeCenter, reference: continuityReference)
                < placementCost(modal, shift: right, center: rangeCenter, reference: continuityReference)
        } ?? 0
        let shifted = modal.map { $0 + shift }
        if shifted.allSatisfy(companionRange.contains) {
            return shifted.map { UInt8(max(0, min(127, $0))) }
        }
        return voiceLedIntoRange(modal, reference: continuityReference).map(UInt8.init)
    }

    public func transposeByScaleDegrees(
        _ pitches: [UInt8],
        steps: Int,
        continuityReference: UInt8? = nil
    ) -> [UInt8] {
        let transformed = pitches.map {
            pitch(forScaleDegree: scaleDegree(for: Int($0)) + steps)
        }
        return placePhrase(transformed.map { UInt8(max(0, min(127, $0))) },
                           continuityReference: continuityReference)
    }

    public func invertByScaleDegrees(
        _ pitches: [UInt8],
        continuityReference: UInt8? = nil
    ) -> [UInt8] {
        guard let first = pitches.first else { return [] }
        let anchor = scaleDegree(for: Int(first))
        let transformed = pitches.map {
            pitch(forScaleDegree: anchor - (scaleDegree(for: Int($0)) - anchor))
        }
        return placePhrase(transformed.map { UInt8(max(0, min(127, $0))) },
                           continuityReference: continuityReference)
    }

    public func scaleDegreeDistance(from: UInt8, to: UInt8) -> Int {
        scaleDegree(for: Int(to)) - scaleDegree(for: Int(from))
    }

    public func cadencePitch(from note: UInt8, previous: UInt8?) -> UInt8 {
        let coordinate = scaleDegree(for: Int(note))
        let approach = previous.map { Int(note) - Int($0) } ?? 0
        let offsets = [-2, -1, 1, 2, 0]
        let candidates = offsets.map { coordinate + $0 }.filter(isStableScaleDegree)
        let chosen = candidates.min { left, right in
            let leftMotion = pitch(forScaleDegree: left) - Int(note)
            let rightMotion = pitch(forScaleDegree: right) - Int(note)
            let leftCost = abs(leftMotion) + (approach * leftMotion > 0 ? 2 : 0)
            let rightCost = abs(rightMotion) + (approach * rightMotion > 0 ? 2 : 0)
            return leftCost == rightCost ? abs(leftMotion) < abs(rightMotion) : leftCost < rightCost
        } ?? coordinate
        let placed = placePhrase(
            [UInt8(max(0, min(127, pitch(forScaleDegree: chosen))))],
            continuityReference: previous
        )
        return placed.first ?? note
    }

    public func cadenceStability(of note: UInt8?) -> Double {
        guard let note else { return 1 }
        let degree = positiveModulo(scaleDegree(for: Int(note)), 7)
        if [0, 2, 4].contains(degree) { return 1 }
        if [1, 3, 5].contains(degree) { return 0.62 }
        return 0.38
    }

    private func modalizePhrase(_ pitches: [Int]) -> [Int] {
        var result: [Int] = []
        for (index, pitch) in pitches.enumerated() {
            let candidates = (-2...2).map { pitch + $0 }.filter {
                (0...127).contains($0) && contains(UInt8($0))
            }
            let previous = result.last
            let sourceInterval = index > 0 ? pitch - pitches[index - 1] : 0
            let chosen = candidates.min { left, right in
                let leftDistance = abs(left - pitch)
                let rightDistance = abs(right - pitch)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                guard let previous else { return left < right }
                let leftIntervalError = abs((left - previous) - sourceInterval)
                let rightIntervalError = abs((right - previous) - sourceInterval)
                return leftIntervalError == rightIntervalError
                    ? left < right
                    : leftIntervalError < rightIntervalError
            } ?? pitch
            result.append(chosen)
        }
        return result
    }

    private func placementCost(
        _ pitches: [Int],
        shift: Int,
        center: Double,
        reference: UInt8?
    ) -> Double {
        let shifted = pitches.map { $0 + shift }
        let outside = shifted.reduce(0) { total, pitch in
            total + max(0, companionRange.lowerBound - pitch)
                + max(0, pitch - companionRange.upperBound)
        }
        let average = Double(shifted.reduce(0, +)) / Double(shifted.count)
        let continuity = reference.map { abs(Double(shifted[0]) - Double($0)) * 0.32 } ?? 0
        return Double(outside) * 100 + abs(average - center) + continuity
    }

    private func voiceLedIntoRange(_ pitches: [Int], reference: UInt8?) -> [Int] {
        var result: [Int] = []
        for (index, pitch) in pitches.enumerated() {
            let pitchClass = positiveModulo(pitch, 12)
            let candidates = companionRange.filter { positiveModulo($0, 12) == pitchClass }
            let expected = index == 0
                ? Int(reference ?? UInt8((companionRange.lowerBound + companionRange.upperBound) / 2))
                : result[index - 1] + (pitch - pitches[index - 1])
            result.append(candidates.min {
                let left = abs($0 - expected)
                let right = abs($1 - expected)
                return left == right ? $0 < $1 : left < right
            } ?? companionRange.lowerBound)
        }
        return result
    }

    private func nearestModalPitch(to pitch: Int, within range: ClosedRange<Int>) -> Int {
        range.filter { contains(UInt8($0)) }.min {
            let left = abs($0 - pitch)
            let right = abs($1 - pitch)
            return left == right ? $0 < $1 : left < right
        } ?? fold(pitch, into: range)
    }

    private func scaleDegree(for pitch: Int) -> Int {
        let projected = nearestModalPitch(to: pitch, within: 0...127)
        let relative = projected - Int(tonalCenterPitchClass)
        let octave = floorDivision(relative, by: 12)
        let pitchClass = positiveModulo(relative, 12)
        let degree = mode.intervals.firstIndex(of: pitchClass) ?? 0
        return octave * 7 + degree
    }

    private func pitch(forScaleDegree coordinate: Int) -> Int {
        let octave = floorDivision(coordinate, by: 7)
        let degree = positiveModulo(coordinate, 7)
        return Int(tonalCenterPitchClass) + octave * 12 + mode.intervals[degree]
    }

    private func isStableScaleDegree(_ coordinate: Int) -> Bool {
        [0, 2, 4].contains(positiveModulo(coordinate, 7))
    }

    private func floorDivision(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func fold(_ note: Int, into range: ClosedRange<Int>) -> Int {
        var result = note
        while result < range.lowerBound { result += 12 }
        while result > range.upperBound { result -= 12 }
        return result
    }
}

public struct ResponseCandidateGenerator: Sendable {
    public init() {}

    public func candidates(
        for motif: Motif,
        pitchContext: ModalPitchContext,
        previousResponse: [ConversationResponseNote] = []
    ) -> [ConversationResponseCandidate] {
        let source = subject(from: motif)
        guard source.count >= 2 else {
            return [restCandidate(confidence: motif.melodyConfidence)]
        }
        let continuity = previousResponse.last?.note
        let echoNotes = shapedNotes(
            source,
            pitches: pitchContext.placePhrase(
                source.map(\.note),
                continuityReference: continuity
            ),
            relationship: .echo
        )
        var tailNotes = echoNotes
        if let last = tailNotes.last {
            tailNotes[tailNotes.count - 1] = ConversationResponseNote(
                note: pitchContext.cadencePitch(
                    from: last.note,
                    previous: tailNotes.dropLast().last?.note
                ),
                velocity: last.velocity,
                relativeOnsetBeats: last.relativeOnsetBeats,
                durationBeats: max(last.durationBeats, 0.42)
            )
        }
        let held = ConversationResponseNote(
            note: pitchContext.cadencePitch(
                from: echoNotes.last?.note ?? echoNotes[0].note,
                previous: echoNotes.dropLast().last?.note
            ),
            velocity: UInt8(max(24, Int(echoNotes.last?.velocity ?? 48) - 8)),
            relativeOnsetBeats: 0,
            durationBeats: min(2, max(0.75, motif.durationBeats * 0.5))
        )
        let clarity = motif.melodyConfidence * motif.boundaryConfidence
        return [
            restCandidate(confidence: clarity),
            ConversationResponseCandidate(
                id: "echo",
                relationship: .echo,
                notes: echoNotes,
                score: score(
                    echoNotes,
                    against: source,
                    relationship: .echo,
                    context: pitchContext,
                    previousResponse: previousResponse
                )
            ),
            ConversationResponseCandidate(
                id: "tail",
                relationship: .tailVariation,
                notes: tailNotes,
                score: score(
                    tailNotes,
                    against: source,
                    relationship: .tailVariation,
                    context: pitchContext,
                    previousResponse: previousResponse
                )
            ),
            ConversationResponseCandidate(
                id: "hold",
                relationship: .hold,
                notes: [held],
                score: score(
                    [held],
                    against: [source.last ?? source[0]],
                    relationship: .hold,
                    context: pitchContext,
                    previousResponse: previousResponse
                )
            )
        ]
    }

    public func developmentCandidates(
        origin: Motif,
        current: Motif,
        pitchContext: ModalPitchContext,
        previousResponse: [ConversationResponseNote] = []
    ) -> [ConversationResponseCandidate] {
        var result = candidates(
            for: current,
            pitchContext: pitchContext,
            previousResponse: previousResponse
        )
        let source = subject(from: origin)
        guard source.count >= 2 else { return result }
        let continuity = previousResponse.last?.note
        let rawShift = pitchContext.scaleDegreeDistance(
            from: source[0].note,
            to: current.notes.first?.note ?? source[0].note
        )
        let currentFirst = current.notes.first?.note ?? source[0].note
        let contourDirection = (current.notes.last?.note ?? currentFirst) >= currentFirst ? 1 : -1
        let transposition = rawShift == 0
            ? contourDirection
            : max(-4, min(4, rawShift))
        let sequence = shapedNotes(
            source,
            pitches: pitchContext.transposeByScaleDegrees(
                source.map(\.note),
                steps: transposition,
                continuityReference: continuity
            ),
            relationship: .sequence
        )
        let inversion = shapedNotes(
            source,
            pitches: pitchContext.invertByScaleDegrees(
                source.map(\.note),
                continuityReference: continuity
            ),
            relationship: .inversion
        )
        let fragmentSource = structuralFragment(from: source)
        let fragment = shapedNotes(
            fragmentSource,
            pitches: pitchContext.placePhrase(
                fragmentSource.map(\.note),
                continuityReference: continuity
            ),
            relationship: .fragmentation
        )
        let augmentation = shapedNotes(
            source,
            pitches: pitchContext.placePhrase(source.map(\.note), continuityReference: continuity),
            relationship: .augmentation,
            onsetScale: 1.5,
            durationScale: 1.35
        )
        let original = shapedNotes(
            source,
            pitches: pitchContext.placePhrase(source.map(\.note), continuityReference: continuity),
            relationship: .originalReturn
        )

        result += [
            developmentCandidate("sequence", .sequence, sequence, source, pitchContext, previousResponse),
            developmentCandidate("inversion", .inversion, inversion, source, pitchContext, previousResponse),
            developmentCandidate("fragment", .fragmentation, fragment, fragmentSource, pitchContext, previousResponse),
            developmentCandidate("augment", .augmentation, augmentation, source, pitchContext, previousResponse),
            developmentCandidate("return", .originalReturn, original, source, pitchContext, previousResponse)
        ]
        return result
    }

    public func subject(from motif: Motif, maximumNotes: Int = 8) -> [MotifNote] {
        guard motif.notes.count > maximumNotes else { return motif.notes }
        var selected = Set([0, motif.notes.count - 1])
        selected.formUnion(motif.features.accentedNoteIndices)
        selected.formUnion(motif.features.restedNoteIndices)
        for interval in motif.features.characteristicIntervalIndices {
            selected.insert(interval)
            selected.insert(min(motif.notes.count - 1, interval + 1))
        }
        let ranked = motif.notes.indices.sorted { left, right in
            let leftScore = motif.notes[left].accent
                + min(1, motif.notes[left].durationBeats) * 0.3
                + (left == motif.notes.count - 1 ? 0.4 : 0)
            let rightScore = motif.notes[right].accent
                + min(1, motif.notes[right].durationBeats) * 0.3
                + (right == motif.notes.count - 1 ? 0.4 : 0)
            return leftScore == rightScore ? left < right : leftScore > rightScore
        }
        for index in ranked where selected.count < maximumNotes { selected.insert(index) }
        return selected.sorted().prefix(maximumNotes).map { motif.notes[$0] }
    }

    private func restCandidate(confidence: Double) -> ConversationResponseCandidate {
        ConversationResponseCandidate(
            id: "rest",
            relationship: .rest,
            notes: [],
            score: ConversationScore(
                recognition: confidence < 0.55 ? 1 : 0.18,
                space: 1,
                voiceLeading: 1,
                modalFit: 1
            )
        )
    }

    private func developmentCandidate(
        _ id: String,
        _ relationship: ConversationRelationship,
        _ notes: [ConversationResponseNote],
        _ source: [MotifNote],
        _ context: ModalPitchContext,
        _ previousResponse: [ConversationResponseNote]
    ) -> ConversationResponseCandidate {
        ConversationResponseCandidate(
            id: id,
            relationship: relationship,
            notes: notes,
            score: score(
                notes,
                against: source,
                relationship: relationship,
                context: context,
                previousResponse: previousResponse
            )
        )
    }

    private func shapedNotes(
        _ source: [MotifNote],
        pitches: [UInt8],
        relationship: ConversationRelationship,
        onsetScale: Double = 1,
        durationScale: Double = 1
    ) -> [ConversationResponseNote] {
        guard source.count == pitches.count, let firstOnset = source.first?.relativeOnsetBeats else {
            return []
        }
        let articulation: Double = switch relationship {
        case .fragmentation: 0.58
        case .inversion: 0.7
        case .sequence: 0.74
        case .tailVariation: 0.78
        case .echo: 0.82
        case .augmentation: 0.86
        case .originalReturn: 0.9
        case .hold, .rest: 1
        }
        return source.indices.map { index in
            let relativeOnset = (source[index].relativeOnsetBeats - firstOnset) * onsetScale
            let gap = index + 1 < source.count
                ? max(0.08, (source[index + 1].relativeOnsetBeats
                    - source[index].relativeOnsetBeats) * onsetScale)
                : Double.greatestFiniteMagnitude
            let desired = max(0.1, source[index].durationBeats * durationScale)
            let duration = index + 1 < source.count
                ? min(desired, gap * articulation)
                : desired * (relationship == .originalReturn ? 1.18 : 1.05)
            let position = source.count > 1 ? Double(index) / Double(source.count - 1) : 0
            let arc = sin(position * .pi) * 5
            let opening = index == 0 ? 4.0 : 0
            let ending = index == source.count - 1 ? -4.0 : 0
            let velocity = Double(source[index].velocity) * 0.66
                + source[index].accent * 7 + arc + opening + ending
            return ConversationResponseNote(
                note: pitches[index],
                velocity: UInt8(max(32, min(88, velocity.rounded()))),
                relativeOnsetBeats: relativeOnset,
                durationBeats: duration
            )
        }
    }

    private func structuralFragment(from source: [MotifNote]) -> [MotifNote] {
        guard source.count > 3 else { return source }
        let middle = source.indices.dropFirst().dropLast().max {
            let left = source[$0].accent + min(1, source[$0].durationBeats) * 0.25
            let right = source[$1].accent + min(1, source[$1].durationBeats) * 0.25
            return left < right
        } ?? source.count / 2
        return [source[0], source[middle], source[source.count - 1]]
    }

    private func score(
        _ notes: [ConversationResponseNote],
        against source: [MotifNote],
        relationship: ConversationRelationship,
        context: ModalPitchContext,
        previousResponse: [ConversationResponseNote]
    ) -> ConversationScore {
        guard !notes.isEmpty else {
            return ConversationScore(
                recognition: 0.1,
                space: 1,
                voiceLeading: 1,
                modalFit: 1,
                contourIntegrity: 0,
                cadence: 1,
                continuity: 1
            )
        }
        let generatedIntervals = intervals(notes.map { Int($0.note) })
        let sourceIntervals = intervals(source.map { Int($0.note) })
        let comparisonCount = min(generatedIntervals.count, sourceIntervals.count)
        let inverted = relationship == .inversion
        let contourMatches = zip(
            generatedIntervals.prefix(comparisonCount),
            sourceIntervals.prefix(comparisonCount)
        ).filter { generated, original in
            generated.signum() == (inverted ? -original.signum() : original.signum())
        }.count
        let contour = comparisonCount == 0
            ? 0.5
            : Double(contourMatches) / Double(comparisonCount)
        let intervalSimilarity: Double
        if comparisonCount == 0 {
            intervalSimilarity = 0.5
        } else {
            var total = 0.0
            for index in 0..<comparisonCount {
                let generated = generatedIntervals[index]
                let original = sourceIntervals[index]
                let difference = abs(abs(generated) - abs(original))
                total += max(0, 1 - Double(difference) / 7)
            }
            intervalSimilarity = total / Double(comparisonCount)
        }
        let sourceRhythm = intervals(source.map { Int(($0.relativeOnsetBeats * 96).rounded()) })
        let generatedRhythm = intervals(notes.map { Int(($0.relativeOnsetBeats * 96).rounded()) })
        let rhythmCount = min(sourceRhythm.count, generatedRhythm.count)
        let rhythm: Double
        if rhythmCount == 0 {
            rhythm = 0.7
        } else {
            var total = 0.0
            for index in 0..<rhythmCount {
                let difference = abs(sourceRhythm[index] - generatedRhythm[index])
                total += max(0, 1 - Double(difference) / 96)
            }
            rhythm = total / Double(rhythmCount)
        }
        let recognition = contour * 0.5 + intervalSimilarity * 0.3 + rhythm * 0.2
        let duration = max(0.25, notes.map {
            $0.relativeOnsetBeats + $0.durationBeats
        }.max() ?? 0.25)
        let density = Double(notes.count) / duration
        let modalCount = notes.filter { context.contains($0.note) }.count
        let continuity: Double = if let previous = previousResponse.last?.note,
                                    let first = notes.first?.note {
            max(0, 1 - Double(abs(Int(first) - Int(previous))) / 14)
        } else {
            0.82
        }
        return ConversationScore(
            recognition: recognition,
            space: max(0.45, 1 - min(1, density / 4) * 0.4),
            voiceLeading: voiceLeading(notes),
            modalFit: Double(modalCount) / Double(notes.count),
            contourIntegrity: contour,
            cadence: context.cadenceStability(of: notes.last?.note),
            continuity: continuity
        )
    }

    private func intervals(_ values: [Int]) -> [Int] {
        zip(values.dropFirst(), values).map { later, earlier in later - earlier }
    }

    private func voiceLeading(_ notes: [ConversationResponseNote]) -> Double {
        guard notes.count > 1 else { return 1 }
        let intervals = zip(notes.dropFirst(), notes).map { later, earlier in
            abs(Int(later.note) - Int(earlier.note))
        }
        let average = Double(intervals.reduce(0, +)) / Double(intervals.count)
        let maximum = intervals.max() ?? 0
        let leapPenalty = maximum > 12 ? Double(maximum - 12) / 12 : 0
        return max(0, 1 - average / 11 - leapPenalty * 0.35)
    }
}

public struct ResponseArbiter: Sendable {
    public init() {}

    public func choose(
        from candidates: [ConversationResponseCandidate]
    ) -> ConversationResponseCandidate? {
        candidates.max {
            if $0.score.total != $1.score.total {
                return $0.score.total < $1.score.total
            }
            return $0.id > $1.id
        }
    }

    public func choose(
        from candidates: [ConversationResponseCandidate],
        context: ConversationDevelopmentContext
    ) -> ConversationResponseCandidate? {
        if context.generation == 0 {
            return candidates.first { $0.relationship == .echo } ?? choose(from: candidates)
        }
        if context.accumulatedDivergence >= 1.2 {
            return candidates.first { $0.relationship == .originalReturn }
        }
        let preferred: ConversationRelationship
        if context.notesPerBeat >= 2.2 {
            preferred = .augmentation
        } else if context.registerShift >= 3 {
            preferred = .sequence
        } else if context.originSimilarity >= 0.78 {
            preferred = .inversion
        } else if context.originDurationBeats >= 2.5 {
            preferred = .fragmentation
        } else {
            preferred = .tailVariation
        }
        let eligible = candidates.filter { $0.relationship != .originalReturn }
        guard let best = choose(from: eligible) else { return choose(from: candidates) }
        guard let contextual = eligible.first(where: { $0.relationship == preferred }) else {
            return best
        }
        return contextual.score.total + 0.16 >= best.score.total ? contextual : best
    }
}

public struct ConversationDevelopmentContext: Codable, Equatable, Sendable {
    public let generation: Int
    public let accumulatedDivergence: Double
    public let originSimilarity: Double
    public let notesPerBeat: Double
    public let registerShift: Int
    public let originDurationBeats: Double

    public init(
        generation: Int,
        accumulatedDivergence: Double,
        originSimilarity: Double,
        notesPerBeat: Double,
        registerShift: Int,
        originDurationBeats: Double
    ) {
        self.generation = generation
        self.accumulatedDivergence = accumulatedDivergence
        self.originSimilarity = originSimilarity
        self.notesPerBeat = notesPerBeat
        self.registerShift = registerShift
        self.originDurationBeats = originDurationBeats
    }
}

public struct ConversationCandidateSummary: Codable, Equatable, Sendable {
    public let id: String
    public let relationship: ConversationRelationship
    public let noteCount: Int
    public let recognition: Double
    public let space: Double
    public let voiceLeading: Double
    public let modalFit: Double
    public let contourIntegrity: Double
    public let cadence: Double
    public let continuity: Double
    public let pitches: [UInt8]
    public let relativeOnsets: [Double]
    public let durations: [Double]
    public let pitchIntervals: [Int]
    public let maximumLeap: Int

    public init(candidate: ConversationResponseCandidate) {
        id = candidate.id
        relationship = candidate.relationship
        noteCount = candidate.notes.count
        recognition = candidate.score.recognition
        space = candidate.score.space
        voiceLeading = candidate.score.voiceLeading
        modalFit = candidate.score.modalFit
        contourIntegrity = candidate.score.contourIntegrity
        cadence = candidate.score.cadence
        continuity = candidate.score.continuity
        pitches = candidate.notes.map(\.note)
        relativeOnsets = candidate.notes.map(\.relativeOnsetBeats)
        durations = candidate.notes.map(\.durationBeats)
        pitchIntervals = zip(pitches.dropFirst(), pitches).map { later, earlier in
            Int(later) - Int(earlier)
        }
        maximumLeap = pitchIntervals.map(abs).max() ?? 0
    }
}

public struct ConversationSelectionInput: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let mode: MusicalMode
    public let originMotifID: UInt64
    public let sourceMotifID: UInt64
    public let context: ConversationDevelopmentContext
    public let candidates: [ConversationCandidateSummary]
    public let localCandidateID: String
    public let tonalCenterPitchClass: UInt8?
    public let tonalCenterConfidence: Double

    public init(
        revision: UInt64,
        mode: MusicalMode,
        originMotifID: UInt64,
        sourceMotifID: UInt64,
        context: ConversationDevelopmentContext,
        candidates: [ConversationCandidateSummary],
        localCandidateID: String,
        tonalCenterPitchClass: UInt8? = nil,
        tonalCenterConfidence: Double = 1
    ) {
        self.revision = revision
        self.mode = mode
        self.originMotifID = originMotifID
        self.sourceMotifID = sourceMotifID
        self.context = context
        self.candidates = candidates
        self.localCandidateID = localCandidateID
        self.tonalCenterPitchClass = tonalCenterPitchClass
        self.tonalCenterConfidence = min(1, max(0, tonalCenterConfidence))
    }
}

public struct ConversationSelectionResolution: Equatable, Sendable {
    public let candidateID: String
    public let source: BassDecisionSource

    public init(candidateID: String, source: BassDecisionSource) {
        self.candidateID = candidateID
        self.source = source
    }
}

public protocol ConversationDecisionProvider: Sendable {
    func prepare(_ input: ConversationSelectionInput)
    func resolution(for input: ConversationSelectionInput) -> ConversationSelectionResolution?
    func expire(revision: UInt64)
    func cancelPendingDecisions()
}

public struct LocalConversationDecisionProvider: ConversationDecisionProvider {
    public init() {}

    public func prepare(_ input: ConversationSelectionInput) {}

    public func resolution(
        for input: ConversationSelectionInput
    ) -> ConversationSelectionResolution? {
        ConversationSelectionResolution(
            candidateID: input.localCandidateID,
            source: .rules
        )
    }

    public func expire(revision: UInt64) {}
    public func cancelPendingDecisions() {}
}

private struct PendingConversation: Sendable {
    let motif: Motif
    let tonalCenterPitchClass: UInt8
    let candidates: [ConversationResponseCandidate]
    let selectionInput: ConversationSelectionInput
    let responseStartMicroseconds: UInt64
    let selectionDeadlineMicroseconds: UInt64
}

private struct PlannedConversationResponse: Sendable {
    let candidate: ConversationResponseCandidate
    var committedNoteCount: Int
    var divergenceApplied: Bool
}

public struct ConversationEngine: Sendable {
    public let musicalStateConfiguration: MusicalStateConfiguration
    public let mode: MusicalMode
    public let outputChannel: UInt8

    private let generator = ResponseCandidateGenerator()
    private let arbiter = ResponseArbiter()
    private let decisionProvider: any ConversationDecisionProvider
    private var originMotif: Motif?
    private var generation = 0
    private var accumulatedDivergence = 0.0
    private var nextResponseID: UInt64 = 1
    private var previousResponseID: UInt64?
    private var previousResponseNotes: [ConversationResponseNote] = []
    private var plannedResponses: [UInt64: PlannedConversationResponse] = [:]
    private var tonalCenterPitchClass: UInt8?
    private var tonalCenterConfidence = 0.0
    private var nextRevision: UInt64 = 1
    private var pendingConversation: PendingConversation?

    public init(
        musicalStateConfiguration: MusicalStateConfiguration,
        mode: MusicalMode,
        outputChannel: UInt8,
        decisionProvider: any ConversationDecisionProvider = LocalConversationDecisionProvider()
    ) {
        self.musicalStateConfiguration = musicalStateConfiguration
        self.mode = mode
        self.outputChannel = outputChannel
        self.decisionProvider = decisionProvider
    }

    public mutating func plan(
        for motif: Motif,
        availableAtMicroseconds: UInt64? = nil
    ) -> BassBarPlan? {
        let availableAt = max(
            motif.finalizedAtMicroseconds,
            availableAtMicroseconds ?? motif.finalizedAtMicroseconds
        )
        guard let prepared = prepareConversation(for: motif) else { return nil }
        let selected = prepared.localSelection
        let start = nextBeat(after: availableAt, beat: beatMicroseconds)
        let plan = finalize(
            motif: motif,
            selected: selected,
            tonalCenterPitchClass: prepared.tonalCenterPitchClass,
            startMicroseconds: start,
            decisionSource: .rules
        )
        for _ in selected.notes {
            if let responseID = plan.conversationLineage?.responseID {
                acknowledgeCommittedResponseNote(responseID: responseID)
            }
        }
        return plan
    }

    public mutating func submit(
        _ motif: Motif,
        availableAtMicroseconds: UInt64
    ) -> BassBarPlan? {
        if let pendingConversation {
            decisionProvider.expire(revision: pendingConversation.selectionInput.revision)
            self.pendingConversation = nil
        }
        guard let prepared = prepareConversation(for: motif) else { return nil }
        let revision = nextRevision
        nextRevision += 1
        let input = ConversationSelectionInput(
            revision: revision,
            mode: mode,
            originMotifID: prepared.originMotifID,
            sourceMotifID: motif.id,
            context: prepared.developmentContext,
            candidates: prepared.candidates.map(ConversationCandidateSummary.init),
            localCandidateID: prepared.localSelection.id,
            tonalCenterPitchClass: prepared.tonalCenterPitchClass,
            tonalCenterConfidence: tonalCenterConfidence
        )
        decisionProvider.prepare(input)
        if let resolution = decisionProvider.resolution(for: input),
           let selected = prepared.candidates.first(where: {
               $0.id == resolution.candidateID
           }) {
            let start = nextBeat(after: availableAtMicroseconds, beat: beatMicroseconds)
            return finalize(
                motif: motif,
                selected: selected,
                tonalCenterPitchClass: prepared.tonalCenterPitchClass,
                startMicroseconds: start,
                decisionSource: resolution.source
            )
        }

        let earliestDecision = availableAtMicroseconds + 350_000
        let responseStart = nextBeat(after: earliestDecision, beat: beatMicroseconds)
        pendingConversation = PendingConversation(
            motif: motif,
            tonalCenterPitchClass: prepared.tonalCenterPitchClass,
            candidates: prepared.candidates,
            selectionInput: input,
            responseStartMicroseconds: responseStart,
            selectionDeadlineMicroseconds: responseStart > 100_000
                ? responseStart - 100_000
                : 0
        )
        return nil
    }

    public mutating func advance(through offsetMicroseconds: UInt64) -> BassBarPlan? {
        guard let pending = pendingConversation else { return nil }
        let resolution = decisionProvider.resolution(for: pending.selectionInput)
        if resolution == nil, offsetMicroseconds < pending.selectionDeadlineMicroseconds {
            return nil
        }
        pendingConversation = nil
        let selected: ConversationResponseCandidate
        let source: BassDecisionSource
        if let resolution,
           let resolved = pending.candidates.first(where: {
               $0.id == resolution.candidateID
           }) {
            selected = resolved
            source = resolution.source
        } else {
            decisionProvider.expire(revision: pending.selectionInput.revision)
            selected = pending.candidates.first {
                $0.id == pending.selectionInput.localCandidateID
            } ?? pending.candidates[0]
            source = .fallback
        }
        let start = offsetMicroseconds < pending.responseStartMicroseconds
            ? pending.responseStartMicroseconds
            : nextBeat(after: offsetMicroseconds, beat: beatMicroseconds)
        return finalize(
            motif: pending.motif,
            selected: selected,
            tonalCenterPitchClass: pending.tonalCenterPitchClass,
            startMicroseconds: start,
            decisionSource: source
        )
    }

    public mutating func yieldToHuman() {
        if let pendingConversation {
            decisionProvider.expire(revision: pendingConversation.selectionInput.revision)
            self.pendingConversation = nil
        }
    }

    public func cancelPendingDecisions() {
        decisionProvider.cancelPendingDecisions()
    }

    /// Advances conversational memory only when a Note On has crossed the
    /// rolling scheduler's commitment horizon.
    public mutating func acknowledgeCommittedResponseNote(responseID: UInt64) {
        guard var planned = plannedResponses[responseID] else { return }
        planned.committedNoteCount = min(
            planned.candidate.notes.count,
            planned.committedNoteCount + 1
        )
        previousResponseID = responseID
        previousResponseNotes = Array(
            planned.candidate.notes.prefix(planned.committedNoteCount)
        )
        if !planned.divergenceApplied {
            if planned.candidate.relationship == .originalReturn {
                accumulatedDivergence = 0
            } else {
                accumulatedDivergence += divergence(for: planned.candidate)
            }
            planned.divergenceApplied = true
        }
        plannedResponses[responseID] = planned
        trimPlannedResponses()
    }

    public mutating func discardUncommittedResponse(responseID: UInt64) {
        guard let planned = plannedResponses[responseID] else { return }
        if planned.committedNoteCount == 0 {
            plannedResponses.removeValue(forKey: responseID)
        }
    }

    private var beatMicroseconds: Double {
        60_000_000 / musicalStateConfiguration.tempoBPM
    }

    private mutating func prepareConversation(for motif: Motif) -> (
        originMotifID: UInt64,
        tonalCenterPitchClass: UInt8,
        developmentContext: ConversationDevelopmentContext,
        candidates: [ConversationResponseCandidate],
        localSelection: ConversationResponseCandidate
    )? {
        if originMotif == nil { originMotif = motif }
        guard let originMotif else { return nil }
        updateTonalCenter(origin: originMotif, current: motif)
        guard let center = tonalCenterPitchClass else {
            return nil
        }
        let pitchContext = ModalPitchContext(mode: mode, tonalCenterPitchClass: center)
        let developmentContext = contextFor(origin: originMotif, current: motif)
        let candidates = generator.developmentCandidates(
            origin: originMotif,
            current: motif,
            pitchContext: pitchContext,
            previousResponse: previousResponseNotes
        )
        guard let selected = arbiter.choose(from: candidates, context: developmentContext) else {
            return nil
        }
        return (originMotif.id, center, developmentContext, candidates, selected)
    }

    private mutating func finalize(
        motif: Motif,
        selected: ConversationResponseCandidate,
        tonalCenterPitchClass center: UInt8,
        startMicroseconds start: UInt64,
        decisionSource: BassDecisionSource
    ) -> BassBarPlan {
        let phrase = render(selected, startMicroseconds: start, beatMicroseconds: beatMicroseconds)
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let decision = decision(for: selected.relationship)
        let responseID = nextResponseID
        let lineage = ConversationLineage(
            originMotifID: originMotif?.id ?? motif.id,
            sourceMotifID: motif.id,
            responseID: responseID,
            parentResponseID: previousResponseID,
            generation: generation,
            relationship: selected.relationship,
            originGesture: motifGesture(generator.subject(from: originMotif ?? motif)),
            sourceGesture: motifGesture(generator.subject(from: motif)),
            responseGesture: responseGesture(selected.notes)
        )
        nextResponseID += 1
        generation += 1
        plannedResponses[responseID] = PlannedConversationResponse(
            candidate: selected,
            committedNoteCount: 0,
            divergenceApplied: false
        )
        return BassBarPlan(
            sourceBarIndex: Int(motif.finalizedAtMicroseconds / barLength),
            targetBarIndex: Int(start / barLength),
            chord: nil,
            usedHeldChord: false,
            decision: decision,
            decisionSource: decisionSource,
            developmentStage: nil,
            tonalCenterPitchClass: center,
            conversationLineage: lineage,
            phrase: phrase,
            expression: expression(for: selected)
        )
    }

    private mutating func updateTonalCenter(origin: Motif, current: Motif) {
        let planner = ModalHarmonyPlanner(mode: mode)
        if tonalCenterPitchClass == nil,
           let assessment = planner.assessTonalCenter(from: origin.legacyMemory().notes) {
            tonalCenterPitchClass = assessment.tonalCenterPitchClass
            tonalCenterConfidence = assessment.confidence
        }
        guard current.id != origin.id,
              tonalCenterConfidence < 0.78,
              let assessment = planner.assessTonalCenter(
                  from: origin.legacyMemory().notes + current.legacyMemory().notes
              ) else {
            return
        }
        if assessment.tonalCenterPitchClass == tonalCenterPitchClass {
            tonalCenterConfidence = max(tonalCenterConfidence, assessment.confidence)
        } else if assessment.confidence >= tonalCenterConfidence + 0.15 {
            tonalCenterPitchClass = assessment.tonalCenterPitchClass
            tonalCenterConfidence = assessment.confidence
        }
    }

    private func motifGesture(_ notes: [MotifNote]) -> [ConversationGesturePoint] {
        guard let first = notes.first else { return [] }
        return notes.map {
            ConversationGesturePoint(
                note: $0.note,
                relativeOnsetBeats: $0.relativeOnsetBeats - first.relativeOnsetBeats,
                durationBeats: $0.durationBeats,
                intensity: $0.accent
            )
        }
    }

    private func responseGesture(
        _ notes: [ConversationResponseNote]
    ) -> [ConversationGesturePoint] {
        notes.map {
            ConversationGesturePoint(
                note: $0.note,
                relativeOnsetBeats: $0.relativeOnsetBeats,
                durationBeats: $0.durationBeats,
                intensity: Double($0.velocity) / 127
            )
        }
    }

    private func contextFor(origin: Motif, current: Motif) -> ConversationDevelopmentContext {
        let originIntervals = origin.features.pitchIntervals
        let currentIntervals = current.features.pitchIntervals
        let comparisons = min(originIntervals.count, currentIntervals.count)
        let similarity = comparisons == 0 ? 0 : zip(
            originIntervals.prefix(comparisons),
            currentIntervals.prefix(comparisons)
        ).map { left, right in
            let contour = left.signum() == right.signum() ? 1.0 : 0.0
            let size = max(0, 1 - Double(abs(abs(left) - abs(right))) / 7)
            return contour * 0.6 + size * 0.4
        }.reduce(0, +) / Double(comparisons)
        let notesPerBeat = Double(current.notes.count) / max(0.25, current.durationBeats)
        let registerShift = abs(
            Int(current.notes.first?.note ?? 60) - Int(origin.notes.first?.note ?? 60)
        )
        return ConversationDevelopmentContext(
            generation: generation,
            accumulatedDivergence: accumulatedDivergence,
            originSimilarity: similarity,
            notesPerBeat: notesPerBeat,
            registerShift: registerShift,
            originDurationBeats: origin.durationBeats
        )
    }

    private func divergence(for candidate: ConversationResponseCandidate) -> Double {
        let structural: Double = switch candidate.relationship {
        case .rest, .hold: 0.15
        case .echo: 0.2
        case .tailVariation: 0.35
        case .sequence: 0.55
        case .fragmentation: 0.6
        case .augmentation: 0.65
        case .inversion: 0.8
        case .originalReturn: 0
        }
        return structural + (1 - candidate.score.recognition) * 0.35
    }

    private mutating func trimPlannedResponses() {
        guard plannedResponses.count > 16 else { return }
        for key in plannedResponses.keys.sorted().prefix(plannedResponses.count - 16) {
            plannedResponses.removeValue(forKey: key)
        }
    }

    private func render(
        _ candidate: ConversationResponseCandidate,
        startMicroseconds: UInt64,
        beatMicroseconds: Double
    ) -> BassPhrase {
        let ordered = candidate.notes.sorted { $0.relativeOnsetBeats < $1.relativeOnsetBeats }
        var messages: [ScheduledMIDIMessage] = []
        for index in ordered.indices {
            let note = ordered[index]
            let onset = startMicroseconds
                + UInt64((note.relativeOnsetBeats * beatMicroseconds).rounded())
            let desiredRelease = onset
                + UInt64((note.durationBeats * beatMicroseconds).rounded())
            let release: UInt64
            if index + 1 < ordered.count {
                let nextOnset = startMicroseconds
                    + UInt64((ordered[index + 1].relativeOnsetBeats * beatMicroseconds).rounded())
                release = min(desiredRelease, max(onset + 1, nextOnset - 1))
            } else {
                release = desiredRelease
            }
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: note.note,
                    velocity: note.velocity
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: release,
                    kind: .noteOff,
                    channel: outputChannel,
                    note: note.note,
                    velocity: 0
                )
            )
        }
        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            return $0.kind == .noteOff && $1.kind == .noteOn
        }
        let end = messages.map(\.offsetMicroseconds).max() ?? startMicroseconds
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        return BassPhrase(
            barIndex: Int(startMicroseconds / barLength),
            startMicroseconds: startMicroseconds,
            endMicroseconds: end,
            messages: messages
        )
    }

    private func nextBeat(after offset: UInt64, beat: Double) -> UInt64 {
        let beatIndex = floor(Double(offset) / beat) + 1
        return UInt64((beatIndex * beat).rounded())
    }

    private func decision(for relationship: ConversationRelationship) -> BassDecision {
        switch relationship {
        case .rest:
            return BassDecision(activity: .rest, relationship: .hold, motion: .root, fill: false, confidence: 1)
        case .echo:
            return BassDecision(activity: .normal, relationship: .follow, motion: .step, fill: false, confidence: 0.9)
        case .tailVariation:
            return BassDecision(activity: .normal, relationship: .contrast, motion: .step, fill: false, confidence: 0.82)
        case .hold:
            return BassDecision(activity: .sparse, relationship: .hold, motion: .root, fill: false, confidence: 0.78)
        case .sequence:
            return BassDecision(activity: .normal, relationship: .follow, motion: .step, fill: false, confidence: 0.82)
        case .inversion:
            return BassDecision(activity: .normal, relationship: .contrast, motion: .leap, fill: false, confidence: 0.78)
        case .fragmentation:
            return BassDecision(activity: .sparse, relationship: .contrast, motion: .step, fill: false, confidence: 0.76)
        case .augmentation:
            return BassDecision(activity: .sparse, relationship: .follow, motion: .step, fill: false, confidence: 0.8)
        case .originalReturn:
            return BassDecision(activity: .normal, relationship: .follow, motion: .root, fill: false, confidence: 0.94)
        }
    }

    private func expression(
        for candidate: ConversationResponseCandidate
    ) -> EnsembleExpression {
        EnsembleExpression(
            memory: candidate.relationship == .echo ? 0.92 : 0.72,
            tension: candidate.relationship == .tailVariation ? 0.48 : 0.28,
            activity: min(1, Double(candidate.notes.count) / 6),
            resonance: candidate.relationship == .hold ? 0.8 : 0.52
        )
    }
}
