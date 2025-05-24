import 'dart:io';

abstract class SdpCommonAttributes {
  Map<String, SdpAttribute>? attributes; //?: Record<string, SdpAttribute>;
  SdpIceAttributes? ice; //?:SdpIceAttributes;
  SdpDtlsAttribute? dtls; //?:SdpDtlsAttribute;
}

class Sdp extends SdpCommonAttributes {
  num? protocolVersion;
  /**
   * The "o=" field gives the originator of the session (her username and the address of the user's host) plus a session
   * identifier and version number:
   */
  SdpOrigin? origin;
  /**
   * The "s=" field is the textual session name. There MUST be one and only one "s=" field per session description. The
   * "s=" field MUST NOT be empty and SHOULD contain ISO 10646 characters (but see also the "a=charset" attribute).
   * If a session has no meaningful name, the value "s= " SHOULD be used (i.e., a single space as the session name).
   */
  String? sessionName;
  /**
   *
   * The "i=" field provides textual information about the session. There MUST be at most one session-level "i="
   * field per session description, and at most one "i=" field per media. If the "a=charset" attribute is present,
   * it specifies the character set used in the "i=" field. If the "a=charset" attribute is not present, the "i="
   * field MUST contain ISO 10646 characters in UTF-8 encoding.
   * A single "i=" field MAY also be used for each media definition. In media definitions, "i=" fields are
   * primarily intended for labelling media streams.  As such, they are most likely to be useful when a single
   * session has more than one distinct media stream of the same media type.  An example would be two different
   * whiteboards, one for slides and one for feedback and questions. The "i=" field is intended to provide a
   * free-form human-readable description of the session or the purpose of a media stream. It is not suitable
   * for parsing by automata.
   */
  String? sessionInformation;
  /**
   * A URI is a Uniform Resource Identifier as used by WWW clients. The URI should be a pointer to additional
   * information about the session. This field is OPTIONAL, but if it is present it MUST be specified before the
   * first media field. No more than one URI field is allowed per session description.
   */
  String? uri;
  String? emailAddress;
  String? phoneNumber;
  List<SdpEncryptionKey>? encryptionKeys;
  /**
   *  The "t=" lines specify the start and stop times for a session. Multiple "t=" lines MAY be used if a session is
   *  active at multiple irregularly spaced times; each additional "t=" line specifies an additional period of time for
   *  which the session will be active. If the session is active at regular times, an "r=" line (see below) should be
   *  used in addition to, and following, a "t=" line -- in which case the "t=" line specifies the start and stop times
   *  of the repeat sequence.
   */
  List<SdpTiming>? timing;
  /**
   * "r=" fields specify repeat times for a session. For example, if a session is active at 10am on Monday and 11am on
   * Tuesday for one hour each week for three months, then the <start-time> in the corresponding "t=" field would be the
   * NTP representation of 10am on the first Monday, the <repeat interval> would be 1 week, the <active duration> would
   * be 1 hour, and the offsets would be zero and 25 hours. The corresponding "t=" field stop time would be the NTP
   * representation of the end of the last session three months later.
   */
  List<SdpRepeatTimes>? repeat;
  List<SdpMediaSection>? media;
  SdpBandwidthInformation? bandwidthInformation;
  SdpConnectionInformation? connectionInformation;
  List<SdpGroup>? group;
}

/**
 * The "o=" field gives the originator of the session (her username and the address of the user's host) plus a session
 * identifier and version number:
 */
class SdpOrigin {
  /**
   * <username> is the user's login on the originating host, or it is "-" if the originating host does not support
   * the concept of user IDs. The <username> MUST NOT contain spaces.
   */
  String? username;
  /**
   * <sess-id> is a numeric string such that the tuple of <username>, <sess-id>, <nettype>, <addrtype>, and
   * <unicast-address> forms a globally unique identifier for the session.  The method of <sess-id> allocation is up
   * to the creating tool, but it has been suggested that a Network Time Protocol (NTP) format timestamp be used to
   * ensure uniqueness
   */
  String? sessId;
  /**
   * <sess-version> is a version number for this session description. Its usage is up to the creating tool, so long as
   * <sess-version> is increased when a modification is made to the session data. Again, it is RECOMMENDED that an NTP
   * format timestamp is used.
   */
  num? sessVersion;
  /**
   * <nettype> is a text string giving the type of network. Initially "IN" is defined to have the meaning "Internet",
   * but other values MAY be registered in the future.
   */
  InternetAddressType? netType;
  /**
   * <addrtype> is a text string giving the type of the address that follows. Initially "IP4" and "IP6" are defined,
   * but other values MAY be registered in the future
   */
  InternetAddressType? addrType; //?: 'IP4' | 'IP6';
  /**
   * <unicast-address> is the address of the machine from which the session was created. For an address type of IP4,
   * this is either the fully qualified domain name of the machine or the dotted-decimal representation of the
   * IP version 4 address of the machine. For an address type of IP6, this is either the fully qualified domain name of
   * the machine or the compressed textual representation of the IP version 6 address of the machine. For both IP4
   * and IP6, the fully qualified domain name is the form that SHOULD be given unless this is unavailable, in which case
   * the globally unique address MAY be substituted. A local IP address MUST NOT be used in any context where the SDP
   * description might leave the scope in which the address is meaningful (for example, a local address MUST NOT be
   * included in an application-level referral that might leave the scope).
   */
  String unicastAddress;

  SdpOrigin(this.username, this.sessId, this.sessVersion, this.netType,
      this.addrType, this.unicastAddress);
}

/**
 *  The "t=" lines specify the start and stop times for a session. Multiple "t=" lines MAY be used if a session is
 *  active at multiple irregularly spaced times; each additional "t=" line specifies an additional period of time for
 *  which the session will be active. If the session is active at regular times, an "r=" line (see below) should be
 *  used in addition to, and following, a "t=" line -- in which case the "t=" line specifies the start and stop times
 *  of the repeat sequence.
 */
class SdpTiming {
  num startTime;
  num stopTime;

  SdpTiming(this.startTime, this.stopTime);
}

/**
 * "r=" fields specify repeat times for a session. For example, if a session is active at 10am on Monday and 11am on
 * Tuesday for one hour each week for three months, then the <start-time> in the corresponding "t=" field would be the
 * NTP representation of 10am on the first Monday, the <repeat interval> would be 1 week, the <active duration> would
 * be 1 hour, and the offsets would be zero and 25 hours. The corresponding "t=" field stop time would be the NTP
 * representation of the end of the last session three months later.
 */
class SdpRepeatTimes {
  num repeatInterval;
  num activeDuration;
  List<num>? offsets;

  SdpRepeatTimes(this.repeatInterval, this.activeDuration, this.offsets);
}

enum Method { clear, base64, uri, prompt }

/**
 * If transported over a secure and trusted channel, the Session Description Protocol MAY be used to convey encryption
 * keys. A simple mechanism for key exchange is provided by the key field ("k="), although this is primarily
 * supported for compatibility with older implementations and its use is NOT RECOMMENDED. Work is in progress to define
 * new key exchange mechanisms for use with SDP [27] [28], and it is expected that new applications will use
 * those mechanisms.
 *
 * A key field is permitted before the first media entry (in which case it applies to all media in the session), or
 * for each media entry as required. The format of keys and their usage are outside the scope of this document, and
 * the key field provides no way to indicate the encryption algorithm to be used, key type, or other information about
 * the key: this is assumed to be provided by the higher-level protocol using SDP. If there is a need to convey this
 * information within SDP, the extensions mentioned previously SHOULD be used. Many security protocols require two
 * keys: one for confidentiality, another for integrity. This specification does not support transfer of two keys.
 */
class SdpEncryptionKey {
  /**
   * The method indicates the mechanism to be used to obtain a usable key by external means, or from the encoded
   * encryption key given. The following methods are defined:
   *
   * clear
   *   The encryption key is included untransformed in this key field. This method MUST NOT be used unless it can be
   *   guaranteed that the SDP is conveyed over a secure channel. The encryption key is interpreted as text according
   *   to the charset attribute; use the "k=base64:" method to convey characters that are otherwise prohibited in SDP.
   *
   * base64
   *   The encryption key is included in this key field but has been base64 encoded because it includes characters
   *   that are prohibited in SDP. This method MUST NOT be used unless it can be guaranteed that the SDP is
   *   conveyed over a secure channel.
   *
   * uri
   *   A Uniform Resource Identifier is included in the key field. The URI refers to the data containing the key,
   *   and may require additional authentication before the key can be returned. When a request is made to the given
   *   URI, the reply should specify the encoding for the key.  The URI is often an Secure Socket Layer/Transport
   *   Layer Security (SSL/TLS)-protected HTTP URI ("https:"), although this is not required.
   *
   * prompt
   *  No key is included in this SDP description, but the session or media stream referred to by this key field
   *  is encrypted. The user should be prompted for the key when attempting to join the session, and this
   *  user-supplied key should then be used to decrypt the media streams.  The use of user-specified keys is
   *  NOT RECOMMENDED, since such keys tend to have weak security properties.
   */
  Method method; //: 'clear' | 'base64' | 'uri' | 'prompt';
  String? encryptionKey;

  SdpEncryptionKey(this.method, this.encryptionKey);
}

/**
 * The OPTIONAL "b=" line (bandwidth-field) denotes the proposed bandwidth to be used by the session or media
 * description. The <bwtype> is an alphanumeric modifier that provides the meaning of the <bandwidth> number. Two
 * values are defined in this specification, but other values MAY be registered in the future
 * (see Section 8 and [RFC3556], [RFC3890]):
 */
class SdpBandwidthInformation {
  /**
   * CT
   *   If the bandwidth of a session is different from the bandwidth implicit from the scope, a "b=CT:" line SHOULD
   *   be supplied for the session giving the proposed upper limit to the bandwidth used
   *   (the "conference total" bandwidth). Similarly, if the bandwidth of bundled media streams [RFC8843] in
   *   an "m=" line is different from the implicit value from the scope, a "b=CT:" line SHOULD be supplied in the
   *   media level. The primary purpose of this is to give an approximate idea as to whether two or more sessions
   *   (or bundled media streams) can coexist simultaneously. Note that a "b=CT:" line gives a total bandwidth figure
   *   for all the media at all endpoints.
   *
   * The Mux Category for "b=CT:" is NORMAL. This is discussed in [RFC8859].
   *
   * AS
   *  The bandwidth is interpreted to be application specific (it will be the application's concept
   *  of maximum bandwidth). Normally, this will coincide with what is set on the application's "maximum bandwidth"
   *  control if applicable. For RTP-based applications, the "b=AS:" line gives the RTP "session bandwidth" as defined
   *  in Section 6.2 of [RFC3550]. Note that a "b=AS:" line gives a bandwidth figure for a single media at
   *  a single endpoint, although there may be many endpoints sending simultaneously.
   *
   * The Mux Category for "b=AS:" is SUM. This is discussed in [RFC8859].
   *
   * [RFC4566] defined an "X-" prefix for <bwtype> names. This was intended for experimental purposes only.
   * Use of the "X-" prefix is NOT RECOMMENDED. Instead new (non "X-" prefix) <bwtype> names SHOULD be defined,
   * and then MUST be registered with IANA in the standard namespace. SDP parsers MUST ignore bandwidth-fields with
   * unknown <bwtype> names. The <bwtype> names MUST be alphanumeric and, although no length limit is given,
   * it is recommended that they be short.
   */
  String bwtype;
  /**
   * The <bandwidth> is interpreted as kilobits per second by default (including the transport and network-layer,
   * but not the link-layer, overhead). The definition of a new <bwtype> modifier MAY specify that the bandwidth is
   * to be interpreted in some alternative unit (the "CT" and "AS" modifiers defined in this memo use the default
   * units).
   */
  num bandwidth;

  SdpBandwidthInformation(this.bwtype, this.bandwidth, {required num bandwidth});
}

/**
 * The "c=" line (connection-field) contains information necessary to establish a network connection.
 * A session description MUST contain either at least one "c=" line in each media description or a single "c=" line
 * at the session level. It MAY contain a single session-level "c=" line and additional media-level "c=" line(s)
 * per-media-description, in which case the media-level values override the session-level settings for the
 * respective media.
 */
class SdpConnectionInformation {
  /**
   * <nettype> is a text string giving the type of network. Initially "IN" is defined to have the meaning "Internet",
   * but other values MAY be registered in the future.
   */
  InternetAddressType? netType; //?: 'IN';
  /**
   * <addrtype> is a text string giving the type of the address that follows. Initially "IP4" and "IP6" are defined,
   * but other values MAY be registered in the future
   */
  InternetAddressType? addrType; //?: 'IP4' | 'IP6';
  /**
   * <base multicast address>[/<ttl>]/<number of addresses>
   */
  String connectionAddress; //: string;

  SdpConnectionInformation(this.netType, this.addrType, this.connectionAddress);
}

enum Direction { sendrecv, sendonly, recvonly, inactive }

class SdpBaseMediaSection extends SdpCommonAttributes {
  String? mid; //?: string;
  Direction? direction; //?: 'sendrecv'|'sendonly'|'recvonly'|'inactive';
  List<num> ports;
  String proto;
  SdpBandwidthInformation? bandwidthInformation;
  SdpConnectionInformation? connectionInformation;
  Map<num, String>? extmap;

  SdpBaseMediaSection(this.mid, this.direction, this.ports, this.proto,
      this.bandwidthInformation, this.connectionInformation, this.extmap);
}

enum Type { audio, video, application, text, message }

class SdpAVMediaSection extends SdpBaseMediaSection {
  Type type; //: 'audio' | 'video';
  List<SdpAVFmtp>? fmt;
  SdpAVMsid? msid;

  SdpAVMediaSection(
      this.type,
      this.msid,
      List<num> ports,
      String proto,
      SdpBandwidthInformation? bandwidthInformation,
      SdpConnectionInformation? connectionInformation,
      Map<num, String>? extmap)
      : super(null, null, ports, proto, bandwidthInformation,
            connectionInformation, extmap);
}

class SdpAVMsid {
  String streamId;
  String trackId;

  SdpAVMsid(this.streamId, this.trackId);
}

class SdpAVFmtp {
  num payloadType;
  String? contentType;
  /**
   * rfc 4585
   */
  List<String>? rtcpFeedback;
  /**
   * RFC 8851 && RFC 6184
   */
  Map<String, dynamic>?
      formatParameters; //?:Record<string,string|number|boolean>

  SdpAVFmtp(this.payloadType, this.contentType, this.rtcpFeedback,
      this.formatParameters);
}

class SdpAppMediaSection extends SdpBaseMediaSection {
  Type type; //: 'application';
  String? description; //?: string;

  SdpAppMediaSection(
      this.type,
      this.description,
      List<num> ports,
      String proto,
      SdpBandwidthInformation? bandwidthInformation,
      SdpConnectionInformation? connectionInformation,
      Map<num, String>? extmap)
      : super(null, null, ports, proto, bandwidthInformation,
            connectionInformation, extmap);
}

class SdpOtherMediaSection extends SdpBaseMediaSection {
  Type type; //: 'text' | 'message' | string;
  List<String>? fmtp; //?: string[];

  SdpOtherMediaSection(
      this.type,
      List<num> ports,
      String proto,
      SdpBandwidthInformation? bandwidthInformation,
      SdpConnectionInformation? connectionInformation,
      Map<num, String>? extmap)
      : super(null, null, ports, proto, bandwidthInformation,
            connectionInformation, extmap);
}

typedef SdpMediaSection
    = dynamic; //SdpAVMediaSection | SdpAppMediaSection | SdpOtherMediaSection;

typedef SdpAttribute = dynamic; //string | boolean | string[] ;

class SdpIceAttributes {
  String ufrag;
  String pwd;
  List<String> options;

  SdpIceAttributes(this.ufrag, this.pwd, this.options);
}

enum Setup { active, passive, actpass }

class SdpDtlsAttribute {
  String algorithm;
  String fingerprint;
  Setup setup;

  SdpDtlsAttribute(this.algorithm, this.fingerprint, this.setup);
}

class SdpPair {
  Sdp offer;
  Sdp answer;

  SdpPair(this.offer, this.answer);
}

enum Token { LS, FID, SRF, ANAT, FEC, DDP, BUNDLE }

/**
 * rfc5888 and rfc9143 groups
 */
class SdpGroup {
  /**
   * Semantics                          Token  Reference
   * ---------------------------------  -----  -----------
   * Lip Synchronization                 LS     [RFC5888]
   * Flow Identification                 FID    [RFC5888]
   * Single Reservation Flow             SRF    [RFC3524]
   * Alternative Network Address Types   ANAT   [RFC4091]
   * Forward Error Correction            FEC    [RFC4756]
   * Decoding Dependency                 DDP    [RFC5583]
   * Bundle                              BUNDLE [RFC9143]
   */
  Token token; //: 'LS'|'FID'|'SRF'|'ANAT'|'FEC'|'DDP'|'BUNDLE'
  List<String> mids;

  SdpGroup(this.token, this.mids);
}


// export {
//   Sdp,
//   SdpPair,
//   SdpGroup,
//   SdpOrigin,
//   SdpTiming,
//   SdpAttribute,
//   SdpRepeatTimes,
//   SdpMediaSection,
//   SdpIceAttributes,
//   SdpEncryptionKey,
//   SdpDtlsAttribute,
//   SdpAVMediaSection,
//   SdpAppMediaSection,
//   SdpOtherMediaSection,
//   SdpBandwidthInformation,
//   SdpConnectionInformation
// }