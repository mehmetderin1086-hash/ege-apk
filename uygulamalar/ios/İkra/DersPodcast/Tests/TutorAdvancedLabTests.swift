import CoreGraphics
import Foundation
import Testing
@testable import Ikra

struct TutorAdvancedLabTests {
    @Test func polynomialRootsHandleDegenerateCasesAndCancellation() {
        #expect(TutorLabMath.roots(a: 0, b: 0, c: 0) == .allReal)
        #expect(TutorLabMath.roots(a: 0, b: 0, c: 2) == .none)
        #expect(TutorLabMath.roots(a: 0, b: 2, c: -6) == .finite([3]))
        #expect(TutorLabMath.roots(a: 1, b: 0, c: 1) == .none)
        #expect(TutorLabMath.roots(a: 1, b: -2, c: 1) == .finite([1]))
        if case .finite(let roots) = TutorLabMath.roots(a: 1, b: 1e8, c: 1) {
            #expect(roots.count == 2)
            #expect(abs(roots[1] + 1e-8) < 1e-14)
            #expect(abs(roots[0] * roots[1] - 1) < 1e-8)
        } else { Issue.record("Expected two real roots") }
    }
    @Test func graphRootsSatisfyEquationAcrossSliderDomain() {
        for a in [-3.0, -0.1, 0, 0.1, 3] {
            for b in [-5.0, 0, 5] {
                for c in [-5.0, 0, 5] {
                    if case .finite(let roots) = TutorLabMath.roots(a: a, b: b, c: c) {
                        for x in roots { #expect(abs(TutorLabMath.polynomial(a: a, b: b, c: c, x: x)) < 1e-7) }
                    }
                }
            }
        }
    }
    @Test func enzymeModelHalfMaximumAndPhysicalBounds() {
        #expect(TutorLabMath.enzymeRate(substrate: 2, km: 2, vmax: 10) == 5)
        #expect(TutorLabMath.enzymeRate(substrate: 0, km: 2, vmax: 10) == 0)
        for s in stride(from: 0.0, through: 20.0, by: 0.1) {
            let rate = TutorLabMath.enzymeRate(substrate: s, km: 2, vmax: 10)
            #expect(rate >= 0 && rate < 10)
        }
        #expect(TutorLabMath.enzymeRate(substrate: -1, km: 2, vmax: 10).isNaN)
    }
    @Test func temperatureUsesKelvinAndLightUsesInverseSquare() {
        let p = TutorLabMath.gasPressure(kelvin: 300, moles: 1, litres: 10)
        #expect(abs(TutorLabMath.gasPressure(kelvin: 600, moles: 1, litres: 10) / p - 2) < 1e-12)
        #expect(abs(TutorLabMath.gasPressure(kelvin: 300, moles: 1, litres: 20) / p - 0.5) < 1e-12)
        let light = TutorLabMath.irradiance(powerWatts: 100, distanceMetres: 2)
        #expect(abs(TutorLabMath.irradiance(powerWatts: 100, distanceMetres: 4) / light - 0.25) < 1e-12)
        #expect(TutorLabMath.gasPressure(kelvin: 0, moles: 1, litres: 1).isNaN)
        #expect(TutorLabMath.irradiance(powerWatts: 10, distanceMetres: 0).isNaN)
    }
    @Test func affectedChildInfersBothUnaffectedParentsAreCarriers() {
        let crosses = TutorPedigree.possible(mother: .unaffected, father: .unaffected, child: .affected)
        #expect(crosses.count == 1)
        #expect(crosses.first?.mother == "Aa")
        #expect(crosses.first?.father == "Aa")
        #expect(crosses.first?.affectedProbability == 0.25)
    }
    @Test func pedigreePreservesUncertaintyAndRejectsContradiction() {
        let crosses = TutorPedigree.possible(mother: .unaffected, father: .unaffected, child: .unaffected)
        #expect(Set(crosses.map(\.mother)) == ["AA", "Aa"])
        #expect(crosses.count == 4)
        #expect(TutorPedigree.possible(mother: .affected, father: .affected, child: .unaffected).isEmpty)
        #expect(TutorPedigree.offspring("bad", "Aa").isEmpty)
        #expect(TutorPedigree.offspring("Aa", "Aa").sorted() == ["AA", "Aa", "Aa", "aa"])
    }
    @Test func draggedGeometryKeepsConstraintsEvenOutsideCanvas() {
        for x in [-10.0, 0.2, 0.5, 0.85, 12] {
            for y in [-10.0, 0.15, 0.4, 0.65, 12] {
                let handle = CGPoint(x: x, y: y)
                let right = TutorGeometryModel.points(.right, handle: handle)
                let dot = (right[1].x - right[0].x) * (right[2].x - right[0].x) + (right[1].y - right[0].y) * (right[2].y - right[0].y)
                #expect(abs(dot) < 1e-12)
                let equal = TutorGeometryModel.points(.equal, handle: handle)
                #expect(abs(TutorGeometryModel.distance(equal[0], equal[2]) - TutorGeometryModel.distance(equal[1], equal[2])) < 1e-12)
                let parallel = TutorGeometryModel.points(.parallel, handle: handle)
                #expect(abs((parallel[1].x - parallel[0].x) - (parallel[2].x - parallel[3].x)) < 1e-12)
                #expect(abs((parallel[1].y - parallel[0].y) - (parallel[2].y - parallel[3].y)) < 1e-12)
                #expect(abs((parallel[3].x - parallel[0].x) - (parallel[2].x - parallel[1].x)) < 1e-12)
                #expect(parallel.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
            }
        }
    }
    @Test func forceAndVelocityMayPointDifferentWaysWithoutLosingContact() {
        let model = TutorForceModel(mass: 2, force: 4, angleDegrees: 0, initialVelocity: -10, time: 2)
        #expect(model.acceleration == 2)
        #expect(model.velocity == -6)
        for angle in [-30.0, 0, 60] {
            let m = TutorForceModel(mass: 2, force: 15, angleDegrees: angle, initialVelocity: 0, time: 5)
            #expect(m.normal > 0)
            #expect(abs(m.normal + m.verticalForce - m.mass * 9.81) < 1e-12)
        }
    }
    @Test func everyReactionConservesAtomsAndChargeWithKnownCoefficients() {
        for reaction in TutorChemistry.reactions {
            #expect(reaction.balanced(reaction.solution))
            #expect(reaction.balanced(reaction.solution.map { $0 * 2 }))
            #expect(!reaction.balanced(Array(repeating: 0, count: reaction.solution.count)))
            #expect(!reaction.balanced([]))
        }
    }
    @Test func balancedAtomsAreInsufficientWithoutBalancedCharge() {
        let half = TutorChemistry.reactions.first { $0.id == "half" }!
        let wrongElectrons = [1, 8, 4, 1, 4]
        #expect(half.counts(wrongElectrons).allSatisfy { $0.left == $0.right })
        #expect(!half.balanced(wrongElectrons))
        #expect(half.charge(wrongElectrons).left == 3)
        #expect(half.charge(wrongElectrons).right == 2)
    }
    @Test func probabilityTracksRealOutcomesAndCapsSessionSize() {
        var rng = SeededRandom(seed: 12345)
        for event in TutorProbability.Event.allCases {
            let trials = TutorProbability.append(10000, event: event, trials: [], using: &rng)
            #expect(trials.count == 10000)
            #expect(trials.last?.id == 10000)
            #expect(abs((trials.last?.frequency ?? 0) - event.theoretical) < 0.025)
            for index in 1..<trials.count {
                let delta = trials[index].successes - trials[index - 1].successes
                #expect(delta == 0 || delta == 1)
            }
            #expect(TutorProbability.append(100, event: event, trials: trials, using: &rng).count == 10000)
        }
    }
    @Test func evidenceExamplesRequireTheActualSupportingPassages() {
        let inference = TutorEvidence.claims.first { $0.kind == .inference }!
        #expect(inference.evidence == [0, 1])
        #expect(TutorEvidence.claims.first { $0.kind == .unsupported }?.evidence.isEmpty == true)
        for claim in TutorEvidence.claims {
            #expect(claim.evidence.allSatisfy { TutorEvidence.sentences.indices.contains($0) })
        }
        #expect(TutorEvidence.split(" Birinci.\n\nİkinci. ") == ["Birinci.", "İkinci."])
    }
    @Test func modelEvidenceMustQuoteTheActualNumberedSource() throws {
        let passage = "Kütüphane cuma kapalıdır.\nPerşembe açıktır."
        let valid = #"{"kind":"direct","evidence":[{"line":1,"quote":"cuma kapalıdır"}],"explanation":"Metinde açıkça belirtilmiş."}"#
        let result = try TutorEvidenceAnalysis.parse(valid, passage: passage)
        #expect(result.evidence == [0])
        #expect(result.kind == .direct)
        let hallucinated = valid.replacingOccurrences(of: "cuma kapalıdır", with: "cumartesi açıktır")
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.parse(hallucinated, passage: passage) }
        let wrongLine = valid.replacingOccurrences(of: "\"line\":1", with: "\"line\":2")
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.parse(wrongLine, passage: passage) }
        let unsupportedWithEvidence = valid.replacingOccurrences(of: "direct", with: "unsupported")
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.parse(unsupportedWithEvidence, passage: passage) }
    }
    @Test func evidencePromptRejectsOversizedInputRatherThanLosingContext() throws {
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.prompt(passage: String(repeating: "x", count: 16001), claim: "İddia") }
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.prompt(passage: "", claim: "İddia") }
        #expect(throws: (any Error).self) { try TutorEvidenceAnalysis.prompt(passage: Array(repeating: "Satır", count: 201).joined(separator: "\n"), claim: "İddia") }
        let prompt = try TutorEvidenceAnalysis.prompt(passage: "Açık.\nKapalı.", claim: "Açık mı?")
        #expect(prompt.contains("1: Açık.") && prompt.contains("2: Kapalı."))
    }
    @Test func evidenceAnnotationsRoundTripWithoutLosingSource() throws {
        let annotation = TutorEvidenceAnnotation(claim: "İddia", passage: "Özgün metin", evidence: ["Özgün metin"], kind: .inference)
        let restored = try JSONDecoder().decode(TutorEvidenceAnnotation.self, from: JSONEncoder().encode(annotation))
        #expect(restored.id == annotation.id)
        #expect(restored.passage == annotation.passage)
        #expect(restored.kind == .inference)
    }
}

private nonisolated struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9e3779b97f4a7c15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}
