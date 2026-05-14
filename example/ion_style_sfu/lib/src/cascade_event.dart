// Phase 11/12 — shared types for the cluster relay bridge between
// the main isolate's UDP hub and the worker isolates' synthetic
// transports. Sendable across `SendPort`s.

/// Kind discriminator for relay frames as carried over the
/// shard↔main bridge.
enum CascadeRelayKind { control, rtp, rtcp }

/// Direction/role of a per-shard cascade bridge.
///
/// * [outbound] — this shard cascades *up* to the session's owner SFU.
///   Created automatically by the worker when [ShardConfig.upstream]
///   is non-null.
/// * [inbound] — this shard *is* the session owner and a remote SFU
///   has cascaded *to* us. Created on demand by the main-isolate
///   coordinator when a `cascade-hello` arrives from an unknown peer.
enum CascadeBridgeRole { outbound, inbound }
