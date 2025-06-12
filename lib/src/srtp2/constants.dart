// lib/srtp/constants.dart
const int labelSRTPEncryption = 0x00;
const int labelSRTPAuthenticationTag = 0x01;
const int labelSRTPSalt = 0x02;

const int labelSRTCPEncryption = 0x03;
const int labelSRTCPAuthenticationTag = 0x04;
const int labelSRTCPSalt = 0x05;

const int seqNumMedian = 1 << 15;
const int seqNumMax = 1 << 16;

// SRTP packet header offsets and lengths
const int RTP_VERSION_OFFSET = 0;
const int RTP_VERSION_LENGTH = 1;
const int RTP_PAD_EXT_CC_OFFSET = 0;
const int RTP_PAD_EXT_CC_LENGTH = 1;
const int RTP_MARKER_PAYLOAD_TYPE_OFFSET = 1;
const int RTP_MARKER_PAYLOAD_TYPE_LENGTH = 1;
const int RTP_SEQUENCE_NUMBER_OFFSET = 2;
const int RTP_SEQUENCE_NUMBER_LENGTH = 2;
const int RTP_TIMESTAMP_OFFSET = 4;
const int RTP_TIMESTAMP_LENGTH = 4;
const int RTP_SSRC_OFFSET = 8;
const int RTP_SSRC_LENGTH = 4;
const int RTP_CSRC_OFFSET = 12; // Start of CSRC list, if CC > 0
const int RTP_FIXED_HEADER_LENGTH = 12; // Version, P, X, CC, M, PT, Sequence Number, Timestamp, SSRC

// RTCP packet header offsets and lengths (simplified for common fields)
const int RTCP_VERSION_OFFSET = 0;
const int RTCP_VERSION_LENGTH = 1;
const int RTCP_PAD_COUNT_RC_OFFSET = 0;
const int RTCP_PAD_COUNT_RC_LENGTH = 1;
const int RTCP_PACKET_TYPE_OFFSET = 1;
const int RTCP_PACKET_TYPE_LENGTH = 1;
const int RTCP_LENGTH_OFFSET = 2;
const int RTCP_LENGTH_LENGTH = 2;
const int RTCP_SSRC_OFFSET = 4;
const int RTCP_SSRC_LENGTH = 4;
const int RTCP_FIXED_HEADER_LENGTH = 8; // Version, P, RC, PT, Length, SSRC