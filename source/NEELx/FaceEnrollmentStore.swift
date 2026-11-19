//
//  FaceEnrollmentStore.swift
//  NEELx
//
//  Persisted encrypted under the same Touch-ID-gated session key as the stored Mac password (see SecureFaceStore);
//  `isLocked`/`reloadIfUnlocked()` let the UI distinguish "locked" from "nothing enrolled."
//

import Foundation
import Observation

struct FaceDepthBaseline: Equatable, Sendable {
    let medianNoseProtrusion: Float
    let medianBackgroundCliff: Float
    let sampleCount: Int
}

struct FaceSample: Codable, Equatable {
    let embedding: [Float]
    /// Which guided-enrollment pose this came from, or nil for untagged captures (e.g. Face Lab's manual capture).
    let pose: String?
    let capturedAt: Date
    /// Vision's capture-quality score (0...1), or nil if unavailable.
    let quality: Float?
    /// Optional 9-zone tilt-invariant 3D facial depth relief vector captured during enrollment via Depth Anything V2.
    let depthSignature: [Float]?
    /// Optional per-sample normalized nose protrusion for personal 3D baseline calibration.
    let noseProtrusion: Float?
    /// Optional per-sample head-to-background depth cliff for personal 3D baseline calibration.
    let backgroundCliff: Float?

    init(
        embedding: [Float],
        pose: String?,
        capturedAt: Date,
        quality: Float?,
        depthSignature: [Float]? = nil,
        noseProtrusion: Float? = nil,
        backgroundCliff: Float? = nil
    ) {
        self.embedding = embedding
        self.pose = pose
        self.capturedAt = capturedAt
        self.quality = quality
        self.depthSignature = depthSignature
        self.noseProtrusion = noseProtrusion
        self.backgroundCliff = backgroundCliff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        embedding = try container.decode([Float].self, forKey: .embedding)
        pose = try container.decodeIfPresent(String.self, forKey: .pose)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        quality = try container.decodeIfPresent(Float.self, forKey: .quality)
        depthSignature = try container.decodeIfPresent([Float].self, forKey: .depthSignature)
        noseProtrusion = try container.decodeIfPresent(Float.self, forKey: .noseProtrusion)
        backgroundCliff = try container.decodeIfPresent(Float.self, forKey: .backgroundCliff)
    }
}

extension FaceSample {
    /// Lives here rather than in a view so Face Lab's debug list and the settings tick strip can't drift apart.
    enum QualityTier {
        /// No score recorded. Never counted as poor.
        case unrated
        case poor
        case fair
        case good
    }

    var qualityTier: QualityTier {
        guard let quality else { return .unrated }
        if quality < 0.4 { return .poor }
        if quality < 0.5 { return .fair }
        return .good
    }
}

struct FaceIdentity: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var samples: [FaceSample]
    /// Which `FaceEmbedder.modelIdentifier` produced these samples — different models' embeddings live in unrelated
    /// vector spaces. See `isStale(comparedTo:)`.
    var modelIdentifier: String
    var embeddingDimension: Int
    var createdAt: Date
    /// Turning off keeps the enrollment intact but excludes it from `activeIdentities`, which unlock scores against.
    var isEnabled: Bool

    init(
        id: UUID,
        name: String,
        samples: [FaceSample],
        modelIdentifier: String,
        embeddingDimension: Int,
        createdAt: Date,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.samples = samples
        self.modelIdentifier = modelIdentifier
        self.embeddingDimension = embeddingDimension
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }

    /// Hand-written so `isEnabled` defaults to `true` when absent — a synthesized decoder would throw on a missing
    /// key and, since the whole store decodes as one array, lose every identity in it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        samples = try container.decode([FaceSample].self, forKey: .samples)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        embeddingDimension = try container.decode(Int.self, forKey: .embeddingDimension)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// The single vector actually compared against at recognition time.
    nonisolated var template: [Float]? {
        FaceEmbedding.average(samples.map(\.embedding))
    }

    /// Personalized 9-zone 3D facial depth relief centroid captured during enrollment, if available.
    nonisolated var depthProfile: [Float]? {
        NeuralDepthAnalyzer.meanSignature(of: samples.compactMap(\.depthSignature))
    }

    /// Personal calibrated 3D depth baseline (median nose protrusion & head-to-background cliff)
    /// across enrolled and adaptive samples, adapting automatically to glasses, beards, and camera FOV.
    nonisolated var depthBaseline: FaceDepthBaseline? {
        let noses = samples.compactMap(\.noseProtrusion).filter { $0.isFinite && $0 > 0.005 }.sorted()
        guard !noses.isEmpty else { return nil }
        let cliffs = samples.compactMap(\.backgroundCliff).filter { $0.isFinite }.sorted()
        let medianNose = noses[noses.count / 2]
        let medianCliff = cliffs.isEmpty ? 0 : cliffs[cliffs.count / 2]
        return FaceDepthBaseline(
            medianNoseProtrusion: medianNose,
            medianBackgroundCliff: medianCliff,
            sampleCount: noses.count
        )
    }

    /// True if samples came from a different embedder than the one currently active — should prompt re-enrollment.
    nonisolated func isStale(comparedTo embedder: FaceEmbedder) -> Bool {
        modelIdentifier != embedder.modelIdentifier
    }
}

enum FaceEnrollmentStoreError: LocalizedError {
    case storeUnreadable

    var errorDescription: String? {
        switch self {
        case .storeUnreadable:
            return "Your enrolled faces couldn't be read, so nothing was saved — writing now would overwrite them."
        }
    }
}

@Observable
@MainActor
final class FaceEnrollmentStore {
    /// Shared so the Face Lab tab and onboarding window observe and persist the same identities, not diverging copies.
    static let shared = FaceEnrollmentStore()

    private(set) var identities: [FaceIdentity] = []
    /// True until a successful load — distinguishes "nothing enrolled yet" from "locked, needs Touch ID."
    private(set) var isLocked = true

    /// Non-nil when unlocked but the encrypted store still couldn't be read (decrypt/decode failure, not a missing key) —
    /// unlike `isLocked`, unlocking again won't fix this.
    private(set) var loadFailure: String?

    /// False until a load succeeds. Guards `persist()` so an unreadable store is never overwritten by an empty array.
    private var hasLoadedSuccessfully = false

    /// Everyone the user hasn't switched off with at least 4 valid 3D samples — what unlock actually scores against. `identities` stays the full list.
    var activeIdentities: [FaceIdentity] {
        identities.filter { $0.isEnabled && $0.samples.count >= 4 }
    }

    /// Whether any fully enrolled identity exists in storage with comprehensive multi-angle coverage.
    var hasValidEnrollment: Bool {
        activeIdentities.contains { $0.samples.count >= 4 }
    }

    private init() {
        reloadIfUnlocked()
        // Reload whenever the session key changes, regardless of call site, so this store can't go stale
        // relative to whichever UI changed the session.
        NotificationCenter.default.addObserver(
            forName: .secureCredentialSessionDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadIfUnlocked()
            }
        }
    }

    /// Re-attempts loading from encrypted storage. A no-op (leaves
    /// `isLocked = true`) if the session isn't unlocked yet.
    func reloadIfUnlocked() {
        guard SecureCredentialManager.isSessionUnlocked else {
            isLocked = true
            return
        }
        do {
            identities = try SecureFaceStore.load()
            hasLoadedSuccessfully = true
            loadFailure = nil
        } catch {
            // Deliberately not `(try? load()) ?? []` — a store we couldn't read isn't an empty store, and the next
            // write must not persist an empty array over a file that still holds every sample.
            identities = []
            loadFailure = error.localizedDescription
        }
        isLocked = false
    }

    /// Adds one captured sample to `name`'s identity (creating it if new). Existing samples from a different embedder
    /// are discarded first, since mixing them would corrupt the template.
    @discardableResult
    func addSample(name: String, embedding: [Float], embedder: FaceEmbedder, pose: String? = nil, quality: Float? = nil) throws -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let sample = FaceSample(embedding: embedding, pose: pose, capturedAt: Date(), quality: quality)

        if let index = identities.firstIndex(where: { $0.name == trimmed }) {
            if identities[index].modelIdentifier != embedder.modelIdentifier {
                identities[index].samples = [sample]
            } else {
                identities[index].samples.append(sample)
            }
            identities[index].modelIdentifier = embedder.modelIdentifier
            identities[index].embeddingDimension = embedder.embeddingDimension
        } else {
            identities.append(FaceIdentity(
                id: UUID(),
                name: trimmed,
                samples: [sample],
                modelIdentifier: embedder.modelIdentifier,
                embeddingDimension: embedder.embeddingDimension,
                createdAt: Date()
            ))
        }
        try persist()
        return true
    }

    /// Commits a whole guided enrollment in a single write. When `existingID` names a known identity, its samples are
    /// replaced wholesale (a recapture is a redo, not an append) and it can be renamed since matching is by id.
    @discardableResult
    func commitEnrollment(
        replacing existingID: UUID?,
        name: String,
        samples: [FaceSample],
        embedder: FaceEmbedder
    ) throws -> FaceIdentity? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !samples.isEmpty else { return nil }

        // Local copy, only assigned once the write succeeds — otherwise a locked session would show an unsaved save.
        var updated = identities
        let committed: FaceIdentity
        if let existingID, let index = updated.firstIndex(where: { $0.id == existingID }) {
            updated[index].name = trimmed
            updated[index].samples = samples
            updated[index].modelIdentifier = embedder.modelIdentifier
            updated[index].embeddingDimension = embedder.embeddingDimension
            committed = updated[index]
        } else {
            // Also the fallback if `existingID` no longer resolves (deleted mid-flow) — saving as new beats discarding.
            committed = FaceIdentity(
                id: UUID(),
                name: trimmed,
                samples: samples,
                modelIdentifier: embedder.modelIdentifier,
                embeddingDimension: embedder.embeddingDimension,
                createdAt: Date()
            )
            updated.append(committed)
        }
        try SecureFaceStore.save(updated)
        identities = updated
        return committed
    }

    /// Case- and diacritic-insensitive, unlike `addSample`'s exact match: "alex"/"Alex"/"Álex" are one person to the
    /// user even though storage would treat them as separate identities. `excluding` lets a recapture keep its own name.
    func nameIsTaken(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return identities.contains {
            $0.id != id
                && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Reverts the in-memory flag if the encrypted write fails, rather than showing a toggle state that isn't on disk.
    func setEnabled(_ isEnabled: Bool, for identityID: UUID) throws {
        guard let index = identities.firstIndex(where: { $0.id == identityID }) else { return }
        let previous = identities[index].isEnabled
        guard previous != isEnabled else { return }
        identities[index].isEnabled = isEnabled
        do {
            try persist()
        } catch {
            identities[index].isEnabled = previous
            throw error
        }
    }

    /// Silently updates an enrolled identity with a high-confidence verified unlock sample (max 3 adaptive
    /// slots, rate-limited to once per 24h) so NEELx naturally adapts to glasses, beards, and lighting drift.
    func recordAdaptiveSample(
        for identityID: UUID,
        embedding: [Float],
        quality: Float?,
        depthSignature: [Float]?,
        noseProtrusion: Float? = nil,
        backgroundCliff: Float? = nil
    ) {
        guard NEELxSettings.shared.adaptiveLearningEnabled,
              hasLoadedSuccessfully,
              SecureCredentialManager.isSessionUnlocked,
              let index = identities.firstIndex(where: { $0.id == identityID }) else { return }

        let adaptivePose = "adaptive"
        let now = Date()
        let existingAdaptive = identities[index].samples.filter { $0.pose == adaptivePose }
        if let latest = existingAdaptive.map(\.capturedAt).max(),
           now.timeIntervalSince(latest) < 24 * 60 * 60 {
            return
        }

        var updated = identities
        var samples = updated[index].samples
        // Keep at most 3 rolling adaptive samples so original 360° enrollment anchors always dominate
        let adaptiveIndices = samples.indices.filter { samples[$0].pose == adaptivePose }
        if adaptiveIndices.count >= 3, let oldestIndex = adaptiveIndices.first {
            samples.remove(at: oldestIndex)
        }
        samples.append(FaceSample(
            embedding: embedding,
            pose: adaptivePose,
            capturedAt: now,
            quality: quality,
            depthSignature: depthSignature,
            noseProtrusion: noseProtrusion,
            backgroundCliff: backgroundCliff
        ))
        updated[index].samples = samples
        if (try? SecureFaceStore.save(updated)) != nil {
            identities = updated
        }
    }

    func delete(_ identity: FaceIdentity) throws {
        identities.removeAll { $0.id == identity.id }
        try persist()
    }

    /// Removes the file outright (rather than writing an empty array) — the teardown path when the session key
    /// itself is being removed, so no orphaned encrypted file is left behind for the next setup to trip over.
    func deleteAll() {
        identities.removeAll()
        SecureFaceStore.deleteAll()
        loadFailure = nil
        hasLoadedSuccessfully = true
    }

    private func persist() throws {
        // Refuses to write when the last load failed, so an unreadable store can't be silently replaced by an empty array.
        guard hasLoadedSuccessfully else {
            throw FaceEnrollmentStoreError.storeUnreadable
        }
        try SecureFaceStore.save(identities)
    }
}
