import Foundation

/// Probability sampler for next-token generation over SmolLM2 logits.
/// Supports temperature scaling, Top-P (nucleus) filtering, and repetition penalties.
public final class SmolLM2Sampler: @unchecked Sendable {
    public var temperature: Float = 0.7
    public var topP: Float = 0.9
    public var repetitionPenalty: Float = 1.1
    
    public init(temperature: Float = 0.7, topP: Float = 0.9, repetitionPenalty: Float = 1.1) {
        self.temperature = max(0.01, temperature)
        self.topP = min(1.0, max(0.1, topP))
        self.repetitionPenalty = max(1.0, repetitionPenalty)
    }
    
    /// Samples the next token ID from raw logit values.
    /// - Parameters:
    ///   - logits: Raw float values across the vocabulary (count should match vocabSize: 49,152).
    ///   - recentTokenIds: Recent generated token IDs used to apply repetition penalties.
    ///   - seed: Optional deterministic probability value in [0, 1) for unit tests.
    /// - Returns: Sampled token ID.
    public func sample(from logits: [Float], recentTokenIds: [Int] = [], seed: Float? = nil) -> Int {
        guard !logits.isEmpty else { return 0 }
        let count = logits.count
        
        // 0. Sanitize invalid logits (NaN, +/- Infinity)
        var sanitizedLogits = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            let val = logits[i]
            if val.isNaN {
                sanitizedLogits[i] = -10000.0
            } else if val.isInfinite {
                sanitizedLogits[i] = val > 0 ? 10000.0 : -10000.0
            } else {
                sanitizedLogits[i] = val
            }
        }
        
        // 1. Apply Repetition Penalty
        var scaledLogits = sanitizedLogits
        if repetitionPenalty > 1.0 && !recentTokenIds.isEmpty {
            let uniqueRecent = Set(recentTokenIds)
            for id in uniqueRecent where id < count {
                if scaledLogits[id] > 0 {
                    scaledLogits[id] /= repetitionPenalty
                } else {
                    scaledLogits[id] *= repetitionPenalty
                }
            }
        }
        
        // 2. Greedy selection if temperature is near-zero
        if temperature <= 0.05 {
            var maxVal = scaledLogits[0]
            var maxIdx = 0
            for i in 1..<count {
                if scaledLogits[i] > maxVal {
                    maxVal = scaledLogits[i]
                    maxIdx = i
                }
            }
            return maxIdx
        }
        
        // 3. Apply Temperature
        let invTemp = 1.0 / temperature
        for i in 0..<count {
            scaledLogits[i] *= invTemp
        }
        
        // 3. Subtract max for numerical stability before exponentiating
        var maxLogit = scaledLogits[0]
        for i in 1..<count {
            if scaledLogits[i] > maxLogit {
                maxLogit = scaledLogits[i]
            }
        }
        
        var exps = [Float](repeating: 0.0, count: count)
        var sumExp: Float = 0.0
        for i in 0..<count {
            let expVal = exp(scaledLogits[i] - maxLogit)
            exps[i] = expVal
            sumExp += expVal
        }
        
        guard sumExp > 0 && !sumExp.isNaN else { return 0 }
        let invSum = 1.0 / sumExp
        var probs = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            probs[i] = exps[i] * invSum
        }
        
        // 4. Top-P (Nucleus) Filtering
        let randomValRaw = seed ?? Float.random(in: 0.0..<1.0)
        let clampedRandom = min(0.999999, max(0.0, randomValRaw))
        
        if topP < 1.0 {
            // Find top candidate indices
            let indexed = probs.enumerated().map { ($0.offset, $0.element) }
            let sorted = indexed.sorted { $0.1 > $1.1 }
            
            var cumProb: Float = 0.0
            var filteredCandidates: [(Int, Float)] = []
            
            for item in sorted {
                filteredCandidates.append(item)
                cumProb += item.1
                if cumProb >= topP {
                    break
                }
            }
            
            // Re-normalize filtered probabilities
            let filteredSum = filteredCandidates.reduce(0.0) { $0 + $1.1 }
            guard filteredSum > 0 else { return sorted.first?.0 ?? 0 }
            
            let randomTarget = clampedRandom * filteredSum
            var running: Float = 0.0
            for candidate in filteredCandidates {
                running += candidate.1
                if running >= randomTarget {
                    return candidate.0
                }
            }
            return filteredCandidates.last?.0 ?? 0
        } else {
            // Standard categorical sampling
            var running: Float = 0.0
            for i in 0..<count {
                running += probs[i]
                if running >= clampedRandom {
                    return i
                }
            }
            return count - 1
        }
    }
}
