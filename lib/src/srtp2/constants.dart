// lib/srtp/constants.dart
const int labelSRTPEncryption = 0x00;
const int labelSRTPAuthenticationTag = 0x01;
const int labelSRTPSalt = 0x02;

const int labelSRTCPEncryption = 0x03;
const int labelSRTCPAuthenticationTag = 0x04;
const int labelSRTCPSalt = 0x05;

const int seqNumMedian = 1 << 15;
const int seqNumMax = 1 << 16;