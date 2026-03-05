/*
      0 1 2 3 4 5 6 7
     +-+-+-+-+-+-+-+-+
     |X|R|N|S|PartID | (REQUIRED)
     +-+-+-+-+-+-+-+-+
X:   |I|L|T|K| RSV   | (OPTIONAL)
     +-+-+-+-+-+-+-+-+
I:   |M| PictureID   | (OPTIONAL)
     +-+-+-+-+-+-+-+-+
L:   |   TL0PICIDX   | (OPTIONAL)
     +-+-+-+-+-+-+-+-+
T/K: |TID|Y| KEYIDX  | (OPTIONAL)
     +-+-+-+-+-+-+-+-+
*/

// https://tools.ietf.org/id/draft-ietf-payload-vp8-05.html
import 'dart:typed_data';

class VP8Packet {
  // Required Header
  late int X; // uint8 /* extended control bits present */
  late int N; // uint8 /* when set to 1 this frame can be discarded */
  late int S; // uint8 /* start of VP8 partition */
  late int PID; // uint8 /* partition index */

  // Extended control bits
  late int I; //uint8; /* 1 if PictureID is present */
  late int L; //uint8; /* 1 if TL0PICIDX is present */
  late int T; //uint8; /* 1 if TID is presenlate t */
  late int K; //uint8; /* 1 if KEYIDX is present */

  // Optional extension
  late int PictureID; //uint16 /* 8 or 16 bits, picture ID */
  late int TL0PICIDX; //uint8  /* 8 bits temporal level zero index */
  late int TID; //uint8  /* 2 bits temporal layer index */
  late int Y; //uint8  /* 1 bit layer sync bit */
  late int KEYIDX; //uint8  /* 5 bits temporal key frame index */

  late Uint8List Payload;

  Uint8List unmarshal(Uint8List payload) {
    // if payload == nil {
    // 	return nil, errors.New("errNilPacket")
    // }

    final payloadLen = payload.length;

    if (payloadLen < 4) {
      throw Exception("errShortPacket");
    }

    int payloadIndex = 0;

    X = (payload[payloadIndex] & 0x80) >> 7;
    N = (payload[payloadIndex] & 0x20) >> 5;
    S = (payload[payloadIndex] & 0x10) >> 4;
    PID = payload[payloadIndex] & 0x07;

    payloadIndex++;

    if (X == 1) {
      I = (payload[payloadIndex] & 0x80) >> 7;
      L = (payload[payloadIndex] & 0x40) >> 6;
      T = (payload[payloadIndex] & 0x20) >> 5;
      K = (payload[payloadIndex] & 0x10) >> 4;
      payloadIndex++;
    }

    if (I == 1) {
      // PID present?
      if (payload[payloadIndex] & 0x80 > 0) {
        // M == 1, PID is 16bit
        PictureID =
            ((payload[payloadIndex] & 0x7F) << 8) | (payload[payloadIndex + 1]);
        payloadIndex += 2;
      } else {
        PictureID = (payload[payloadIndex]);
        payloadIndex++;
      }
    }

    if (payloadIndex >= payloadLen) {
      throw Exception("errShortPacket");
    }

    if (L == 1) {
      TL0PICIDX = payload[payloadIndex];
      payloadIndex++;
    }

    if (payloadIndex >= payloadLen) {
      throw Exception("errShortPacket");
    }

    if (T == 1 || K == 1) {
      if (T == 1) {
        TID = payload[payloadIndex] >> 6;
        Y = (payload[payloadIndex] >> 5) & 0x1;
      }
      if (K == 1) {
        KEYIDX = payload[payloadIndex] & 0x1F;
      }
      payloadIndex++;
    }

    if (payloadIndex >= payloadLen) {
      throw Exception("errShortPacket");
    }
    Payload = payload.sublist(payloadIndex);
    return Payload;
  }
}
