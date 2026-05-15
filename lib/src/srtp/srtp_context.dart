import 'dart:typed_data';

import 'rtp2.dart'; // Changed import
import 'constants.dart';
import 'crypto_gcm.dart';
import 'protection_profiles.dart';

class SRTPContext {
  // final InternetAddress addr;
  // final RawDatagramSocket conn;
  final ProtectionProfile protectionProfile;

  /// Cipher used to decrypt traffic *received* from the peer.
  GCM? inboundGcm;

  /// Cipher used to encrypt traffic *sent* to the peer.
  GCM? outboundGcm;

  /// Backward-compatible alias. Older call sites assigned a single `gcm`
  /// cipher and used it for both directions; we mirror writes to both
  /// inbound and outbound so existing code keeps working.
  GCM? get gcm => inboundGcm;
  set gcm(GCM? v) {
    inboundGcm = v;
    outboundGcm ??= v;
  }

  final Map<int, SsrcState> srtpSsrcStates; // For decryption
  final Map<int, SsrcStateEncryption>
      srtpSsrcStatesEncryption; // For encryption

  /// Per-SSRC outbound SRTCP index counter (31-bit, monotonically increasing).
  final Map<int, int> _srtcpOutIndex = {};

  /// Per-SSRC inbound SRTCP replay protection: highest index already
  /// authenticated, plus a 64-entry sliding bitmap of indices below it.
  /// SRTCP indices are 31 bits, monotonically increasing within a
  /// session; replays MUST be rejected (RFC 3711 §3.3.2).
  final Map<int, _SrtcpReplay> _srtcpInboundReplay = {};

  /// Per-SSRC inbound SRTP replay protection. Per RFC 3711 §3.3.2 the
  /// receiver MUST drop any packet whose 48-bit index (`ROC*2^16 +
  /// SEQ`) falls outside the sliding window of the highest-seen
  /// authenticated index. Same shape as [_srtcpInboundReplay] but
  /// keyed off the 48-bit SRTP index.
  final Map<int, _SrtpReplay> _srtpInboundReplay = {};

  /// Number of inbound SRTP packets rejected by [_srtpInboundReplay].
  /// Surfaced for stats / detection of replay attacks.
  int srtpReplayDrops = 0;

  /// 2^48 packet limit (per the AES-GCM SRTP profile, RFC 7714 §17). At
  /// this point the master key MUST be re-derived. We don't currently
  /// support rekeying — instead encrypt fails fast so the application
  /// learns about it instead of silently producing weak ciphertext.
  static const int _maxOutboundPackets = (1 << 48) - 1;

  /// 2^31 SRTCP index limit. Wrapping silently would shadow earlier
  /// packets in our replay window and break authentication on the
  /// other side; throw instead.
  static const int _maxSrtcpIndex = 0x7FFFFFFF;

  /// Total RTP packets encrypted with the current outbound key.
  int _outboundRtpCount = 0;

  /// True once [close] has been called. After that every encrypt /
  /// decrypt fast-fails: the GCM ciphers are zeroized and any further
  /// use would either crash or, worse, produce garbage that looks
  /// almost-valid.
  bool _closed = false;

  bool get isClosed => _closed;

  /// Total number of RTP packets we've successfully encrypted with the
  /// current outbound key. Surfaced for stats / rekey-thresholds.
  int get outboundRtpPacketCount => _outboundRtpCount;

  SRTPContext({
    // required this.addr,
    // required this.conn,
    required this.protectionProfile,
  })  : srtpSsrcStates = {},
        srtpSsrcStatesEncryption = {}; // Initialize new map

  /// Tear down this context. Drops the GCM ciphers (so any caller who
  /// still holds a reference fast-fails with a clear error) and clears
  /// per-SSRC state. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    inboundGcm = null;
    outboundGcm = null;
    srtpSsrcStates.clear();
    srtpSsrcStatesEncryption.clear();
    _srtcpOutIndex.clear();
    _srtcpInboundReplay.clear();
    _srtpInboundReplay.clear();
  }

  // For decryption
  SsrcState _getSrtpSsrcState(int ssrc) {
    if (srtpSsrcStates.containsKey(ssrc)) {
      return srtpSsrcStates[ssrc]!;
    }
    final s = SsrcState(ssrc: ssrc);
    srtpSsrcStates[ssrc] = s;
    return s;
  }

  // For encryption
  SsrcStateEncryption _getSrtpSsrcStateForEncryption(int ssrc) {
    if (srtpSsrcStatesEncryption.containsKey(ssrc)) {
      return srtpSsrcStatesEncryption[ssrc]!;
    }
    final s = SsrcStateEncryption(ssrc: ssrc);
    srtpSsrcStatesEncryption[ssrc] = s;
    return s;
  }

  Future<Uint8List> decryptRtpPacket(Packet packet) async {
    if (_closed) {
      throw StateError('SRTPContext is closed');
    }
    final cipher = inboundGcm;
    if (cipher == null) {
      throw Exception("GCM cipher not initialized for SRTPContext (inbound)");
    }

    final SsrcState s = _getSrtpSsrcState(packet.header.ssrc);
    final RolloverCountResult rocResult =
        s.nextRolloverCount(packet.header.sequenceNumber);

    // RFC 3711 §3.3.2 — anti-replay. The 48-bit SRTP packet index is
    // `ROC*2^16 + SEQ`; reject any packet whose index has already been
    // authenticated, or which is more than [_SrtpReplay._windowSize]
    // packets older than the highest-seen index. The check happens
    // *before* AEAD verify so a replay flood doesn't burn CPU on
    // crypto, and the commit happens *after* a successful verify so a
    // forged packet can't poison the window.
    final replay =
        _srtpInboundReplay.putIfAbsent(packet.header.ssrc, _SrtpReplay.new);
    final index = (rocResult.roc << 16) | packet.header.sequenceNumber;
    if (!replay.check(index)) {
      srtpReplayDrops++;
      throw StateError(
          'SRTP replay: ssrc=0x${packet.header.ssrc.toRadixString(16)} '
          'index=$index');
    }

    // The decrypt method in GCM returns the full decrypted packet (header + payload)
    final Uint8List result = await cipher.decrypt(packet, rocResult.roc);
    rocResult.updateRoc(); // Update decryption ROC after successful decryption
    replay.commit(index);
    // Return only the payload portion
    // return Uint8List.fromList(result.sublist(packet.headerSize));
    return result;
  }

  Future<Uint8List> encryptRtpPacket(Packet packet) async {
    if (_closed) {
      throw StateError('SRTPContext is closed');
    }
    final cipher = outboundGcm;
    if (cipher == null) {
      throw Exception("GCM cipher not initialized for SRTPContext (outbound)");
    }
    if (_outboundRtpCount >= _maxOutboundPackets) {
      throw StateError(
          'SRTP outbound packet limit (2^48) reached \u2014 rekey required');
    }

    final SsrcStateEncryption s =
        _getSrtpSsrcStateForEncryption(packet.header.ssrc);

    // Update the ROC and sequence number for encryption.
    // RTP sequence numbers are strictly monotonically increasing for a
    // given SSRC. Only treat a *strictly smaller* incoming seq as a
    // wrap-around. An equal seq is a duplicate / misuse and bumping
    // the ROC there would corrupt the IV and produce ciphertext the
    // peer can't authenticate.
    if (s.lastSequenceNumber != -1 &&
        packet.header.sequenceNumber < s.lastSequenceNumber) {
      // Sequence number wrapped around (mod 2^16); bump ROC.
      s.roc++;
    }
    s.lastSequenceNumber = packet.header.sequenceNumber;

    final Uint8List result = await cipher.encrypt(packet, s.roc);
    _outboundRtpCount++;
    return result;
  }

  /// Encrypt a full RTCP packet [rtcp] using the outbound cipher. The
  /// per-SSRC SRTCP index is allocated automatically.
  Future<Uint8List> encryptRtcpPacket(Uint8List rtcp) async {
    if (_closed) {
      throw StateError('SRTPContext is closed');
    }
    final cipher = outboundGcm;
    if (cipher == null) {
      throw Exception('GCM cipher not initialized for SRTPContext (outbound)');
    }
    if (rtcp.length < 8) {
      throw Exception('RTCP packet too short');
    }
    final ssrc = ByteData.sublistView(rtcp, 4, 8).getUint32(0, Endian.big);
    final next = (_srtcpOutIndex[ssrc] ?? 0) + 1;
    if (next > _maxSrtcpIndex) {
      throw StateError(
          'SRTCP index space exhausted for ssrc=0x${ssrc.toRadixString(16)} '
          '\u2014 rekey required');
    }
    _srtcpOutIndex[ssrc] = next;
    return cipher.encryptRtcp(rtcp, next);
  }

  /// Decrypt a full SRTCP packet [srtcp] using the inbound cipher.
  Future<Uint8List> decryptRtcpPacket(Uint8List srtcp) async {
    if (_closed) {
      throw StateError('SRTPContext is closed');
    }
    final cipher = inboundGcm;
    if (cipher == null) {
      throw Exception('GCM cipher not initialized for SRTPContext (inbound)');
    }
    if (srtcp.length < 12) {
      throw Exception('SRTCP packet too short');
    }
    // Replay protection: the SRTCP index is the trailing 31 bits of the
    // last 4 bytes of the packet (the SRTCP_INDEX_E trailer per RFC
    // 3711 §3.4 / RFC 7714). Reject duplicates BEFORE touching the GCM
    // cipher so an attacker can't force us to perform expensive AEAD
    // work on every replayed packet.
    final ssrc = ByteData.sublistView(srtcp, 4, 8).getUint32(0, Endian.big);
    final trailerOffset = srtcp.length - 4;
    final eIndex = ByteData.sublistView(srtcp, trailerOffset, srtcp.length)
        .getUint32(0, Endian.big);
    final index = eIndex & _maxSrtcpIndex;
    final replay = _srtcpInboundReplay.putIfAbsent(ssrc, _SrtcpReplay.new);
    if (!replay.check(index)) {
      throw StateError(
          'SRTCP replay: ssrc=0x${ssrc.toRadixString(16)} index=$index');
    }
    final out = await cipher.decryptRtcp(srtcp);
    replay.commit(index);
    return out;
  }
}

/// Sliding-window replay protection for SRTCP indices on a single SSRC.
/// `_top` is the highest index we've authenticated so far; `_bitmap` is
/// a 64-bit window of indices in `(_top - 64, _top]` already seen.
class _SrtcpReplay {
  static const int _windowSize = 64;
  int _top = 0;
  int _bitmap = 0; // bit i set => index (_top - i) already seen
  bool _initialized = false;

  /// Returns true if [index] has not yet been seen and may be processed.
  /// Does NOT commit; call [commit] once the AEAD verify succeeds.
  bool check(int index) {
    if (!_initialized) return true;
    if (index > _top) return true;
    final diff = _top - index;
    if (diff >= _windowSize) return false; // too old
    return (_bitmap & (1 << diff)) == 0;
  }

  /// Mark [index] as seen. Must only be called after [check] returned
  /// true and the packet successfully authenticated.
  void commit(int index) {
    if (!_initialized) {
      _initialized = true;
      _top = index;
      _bitmap = 1; // bit 0 set => _top itself seen
      return;
    }
    if (index > _top) {
      final shift = index - _top;
      if (shift >= _windowSize) {
        _bitmap = 1;
      } else {
        _bitmap = ((_bitmap << shift) | 1) & ((1 << _windowSize) - 1);
      }
      _top = index;
    } else {
      final diff = _top - index;
      if (diff < _windowSize) {
        _bitmap |= 1 << diff;
      }
    }
  }
}

/// Sliding-window replay protection for SRTP packet indices on a
/// single SSRC. Identical algorithm to [_SrtcpReplay] but operates on
/// 48-bit indices (`ROC*2^16 + SEQ`, RFC 3711 §3.3.1).
class _SrtpReplay {
  static const int _windowSize = 64;
  int _top = 0;
  int _bitmap = 0;
  bool _initialized = false;

  bool check(int index) {
    if (!_initialized) return true;
    if (index > _top) return true;
    final diff = _top - index;
    if (diff >= _windowSize) return false;
    return (_bitmap & (1 << diff)) == 0;
  }

  void commit(int index) {
    if (!_initialized) {
      _initialized = true;
      _top = index;
      _bitmap = 1;
      return;
    }
    if (index > _top) {
      final shift = index - _top;
      if (shift >= _windowSize) {
        _bitmap = 1;
      } else {
        _bitmap = ((_bitmap << shift) | 1) & ((1 << _windowSize) - 1);
      }
      _top = index;
    } else {
      final diff = _top - index;
      if (diff < _windowSize) {
        _bitmap |= 1 << diff;
      }
    }
  }
}

class SsrcState {
  final int ssrc;
  int index;
  bool rolloverHasProcessed;

  SsrcState({
    required this.ssrc,
    this.index = 0,
    this.rolloverHasProcessed = false,
  });

  RolloverCountResult nextRolloverCount(int sequenceNumber) {
    final int seq = sequenceNumber;
    final int localRoc = index >> 16;
    final int localSeq = index & (seqNumMax - 1);

    int guessRoc = localRoc;
    int difference = 0;

    if (rolloverHasProcessed) {
      if (index > seqNumMedian) {
        if (localSeq < seqNumMedian) {
          if (seq - localSeq > seqNumMedian) {
            guessRoc = localRoc - 1;
            difference = seq - localSeq - seqNumMax;
          } else {
            guessRoc = localRoc;
            difference = seq - localSeq;
          }
        } else {
          if (localSeq - seqNumMedian > seq) {
            guessRoc = localRoc + 1;
            difference = seq - localSeq + seqNumMax;
          } else {
            guessRoc = localRoc;
            difference = seq - localSeq;
          }
        }
      } else {
        // localRoc is equal to 0
        difference = seq - localSeq;
      }
    }

    Function updateRoc = () {
      if (!rolloverHasProcessed) {
        index |= sequenceNumber;
        rolloverHasProcessed = true;
        return;
      }
      if (difference > 0) {
        index += difference;
      }
    };

    return RolloverCountResult(guessRoc, updateRoc);
  }
}

class RolloverCountResult {
  final int roc;
  final Function updateRoc;

  RolloverCountResult(this.roc, this.updateRoc);
}

class SsrcStateEncryption {
  final int ssrc;
  int roc; // Roll-over counter
  int lastSequenceNumber; // Last sequence number seen for encryption

  SsrcStateEncryption({
    required this.ssrc,
    this.roc = 0,
    this.lastSequenceNumber = -1, // -1 indicates no sequence number seen yet
  });
}
