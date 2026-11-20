import Foundation
public enum ModelNames {
    public enum Supertonic3 {
        public static let textEncoder = "TextEncoder"
        public static let durationPredictor = "DurationPredictor"
        public static let vectorEstimator = "VectorEstimator"
        public static let vocoder = "Vocoder"

        public static let textEncoderFile = textEncoder + ".mlmodelc"
        public static let durationPredictorFile = durationPredictor + ".mlmodelc"
        public static let vectorEstimatorFile = vectorEstimator + ".mlmodelc"
        public static let vocoderFile = vocoder + ".mlmodelc"

        public static let configFile = "tts.json"
        public static let unicodeIndexerFile = "unicode_indexer.json"

        /// The four CoreML bundles required by `Supertonic3Synthesizer`.
        public static let requiredModels: Set<String> = [
            textEncoderFile,
            durationPredictorFile,
            vectorEstimatorFile,
            vocoderFile,
        ]

        /// Models + companion JSON files the downloader must fetch.
        public static let requiredFiles: Set<String> =
            requiredModels.union([configFile, unicodeIndexerFile])

        // MARK: VectorEstimator variants

        /// The three modules shared by every VectorEstimator variant.
        public static let sharedModelFiles: Set<String> = [
            textEncoderFile, durationPredictorFile, vocoderFile,
        ]
        public static let companionFiles: Set<String> = [configFile, unicodeIndexerFile]

        /// Fixed latent buckets published for ANE residency (smallest ≥ chunk
        /// length is selected at synthesis time).
        public static let aneBuckets: [Int] = [128, 256, 512]

        /// Quantized / fixed-length VectorEstimator builds live under this repo
        /// subdirectory; the FP16 dynamic model + the 3 shared modules sit at
        /// the repo root.
        public static let variantsSubdir = "VectorEstimatorVariants"

        /// Bundle (dir) name of a VectorEstimator build, e.g.
        /// `VectorEstimator`, `VectorEstimator_int4`, `VectorEstimator_L256_int8`.
        public static func vectorEstimatorName(precisionSuffix: String?, bucket: Int?) -> String {
            var name = vectorEstimator
            if let bucket { name += "_L\(bucket)" }
            if let precisionSuffix { name += "_\(precisionSuffix)" }
            return name
        }

        /// Repo-relative `.mlmodelc` path for a VectorEstimator build. FP16
        /// dynamic stays at the root; every quantized/bucketed variant is under
        /// `variantsSubdir`.
        public static func vectorEstimatorFile(precisionSuffix: String?, bucket: Int?) -> String {
            let base = vectorEstimatorName(precisionSuffix: precisionSuffix, bucket: bucket) + ".mlmodelc"
            if precisionSuffix == nil && bucket == nil { return base }
            return "\(variantsSubdir)/\(base)"
        }

        /// Files to fetch for a given VectorEstimator download variant token
        /// (see `Supertonic3VectorEstimator.downloadVariant`). `nil` ⇒ the
        /// historical FP16 dynamic model.
        public static func requiredFiles(veVariant: String?) -> Set<String> {
            var set = sharedModelFiles.union(companionFiles)
            switch veVariant {
            case .some(let v) where v.hasPrefix("dyn-"):
                set.insert(vectorEstimatorFile(precisionSuffix: String(v.dropFirst(4)), bucket: nil))
            case .some(let v) where v.hasPrefix("ane-"):
                let q = String(v.dropFirst(4))
                for b in aneBuckets {
                    set.insert(vectorEstimatorFile(precisionSuffix: q, bucket: b))
                }
            default:
                set.insert(vectorEstimatorFile)  // fp16 dynamic
            }
            return set
        }
    }

}
