// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// package rangecoding

// Decoder implements rfc6716#section-4.1
// Opus uses an entropy coder based on range coding [RANGE-CODING]
// [MARTIN79], which is itself a rediscovery of the FIFO arithmetic code
// introduced by [CODING-THESIS].  It is very similar to arithmetic
// encoding, except that encoding is done with digits in any base
// instead of with bits, so it is faster when using larger bases (i.e.,
// a byte).  All of the calculations in the range coder must use bit-
// exact integer arithmetic.
//
// Symbols may also be coded as "raw bits" packed directly into the
// bitstream, bypassing the range coder.  These are packed backwards
// starting at the end of the frame, as illustrated in Figure 12.  This
// reduces complexity and makes the stream more resilient to bit errors,
// as corruption in the raw bits will not desynchronize the decoding
// process, unlike corruption in the input to the range decoder.  Raw
// bits are only used in the CELT layer.
//
//	 0                   1                   2                   3
//	 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//	| Range coder data (packed MSB to LSB) ->                       :
//	+                                                               +
//	:                                                               :
//	+     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//	:     | <- Boundary occurs at an arbitrary bit position         :
//	+-+-+-+                                                         +
//	:                          <- Raw bits data (packed LSB to MSB) |
//	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//	Legend:
//
//	LSB = Least Significant Bit
//	MSB = Most Significant Bit
//
//	     Figure 12: Illustrative Example of Packing Range Coder
//	                        and Raw Bits Data
//
// Each symbol coded by the range coder is drawn from a finite alphabet
// and coded in a separate "context", which describes the size of the
// alphabet and the relative frequency of each symbol in that alphabet.
//
// Suppose there is a context with n symbols, identified with an index
// that ranges from 0 to n-1.  The parameters needed to encode or decode
// symbol k in this context are represented by a three-tuple
// (fl[k], fh[k], ft), all 16-bit unsigned integers, with
// 0 <= fl[k] < fh[k] <= ft <= 65535.  The values of this tuple are
// derived from the probability model for the symbol, represented by
// traditional "frequency counts".  Because Opus uses static contexts,
// those are not updated as symbols are decoded.  Let f[i] be the
// frequency of symbol i.  Then, the three-tuple corresponding to symbol
// k is given by the following:
//
//	        k-1                                   n-1
//	        __                                    __
//	fl[k] = \  f[i],  fh[k] = fl[k] + f[k],  ft = \  f[i]
//	        /_                                    /_
//	        i=0                                   i=0
//
// The range decoder extracts the symbols and integers encoded using the
// range encoder in Section 5.1.  The range decoder maintains an
// internal state vector composed of the two-tuple (val, rng), where val
// represents the difference between the high end of the current range
// and the actual coded value, minus one, and rng represents the size of
// the current range.  Both val and rng are 32-bit unsigned integer
// values.
import 'dart:typed_data';

class Decoder {
  Uint8List data; //     []byte
  int bitsRead = 0; // uint

  int rangeSize = 128; //              uint32 // rng in RFC 6716
  late int highAndCodedDifference; // uint32 // val in RFC 6716

  Decoder(this.data) {
    highAndCodedDifference = 127 - getBits(7);
  }

  int getBit() {
    final index = (bitsRead / 8).toInt();
    final offset = bitsRead % 8;

    if (index > (data.length) - 1) {
      //nolint:gosec // G115
      return 0;
    }

    bitsRead++;

    return (data[index] >> (7 - offset)) & 1;
  }

  int getBits(int n) {
    int bits = 0;

    for (int i = 0; i < n; i++) {
      if (i != 0) {
        bits <<= 1;
      }

      bits |= getBit();
    }

    return bits;
  }

// To normalize the range, the decoder repeats the following process,
// implemented by ec_dec_normalize() (entdec.c), until rng > 2**23.  If
// rng is already greater than 2**23, the entire process is skipped.
// First, it sets rng to (rng<<8).  Then, it reads the next byte of the
// Opus frame and forms an 8-bit value sym, using the leftover bit
// buffered from the previous byte as the high bit and the top 7 bits of
// the byte just read as the other 7 bits of sym.  The remaining bit in
// the byte just read is buffered for use in the next iteration.  If no
// more input bytes remain, it uses zero bits instead.  See
// Section 4.1.1 for the initialization used to process the first byte.
// Then, it sets
//
// val = ((val<<8) + (255-sym)) & 0x7FFFFFFF
//
// https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.2.1
  void normalize() {
    while (rangeSize <= minRangeSize) {
      rangeSize <<= 8;
      highAndCodedDifference =
          ((highAndCodedDifference << 8) + (255 - getBits(8))) & 0x7FFFFFFF;
    }
  }

// Init sets the state of the Decoder
// Let b0 be an 8-bit unsigned integer containing first input byte (or
// containing zero if there are no bytes in this Opus frame).  The
// decoder initializes rng to 128 and initializes val to (127 -
//
//	(b0>>1)), where (b0>>1) is the top 7 bits of the first input byte.
//
// It saves the remaining bit, (b0&1), for use in the renormalization
// procedure described in Section 4.1.2.1, which the decoder invokes
// immediately after initialization to read additional bits and
// establish the invariant that rng > 2**23.
//
// https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.1
  void init(Uint8List data) {
    this.data = data;
    bitsRead = 0;

    rangeSize = 128;
    highAndCodedDifference = 127 - getBits(7);
    normalize();
  }

  void update(int scale, int low, int high, int total) {
    highAndCodedDifference -= scale * (total - high);
    if (low != 0) {
      rangeSize = scale * (high - low);
    } else {
      rangeSize -= scale * (total - high);
    }

    normalize();
  }

// DecodeSymbolLogP decodes a single binary symbol.
// The context is described by a single parameter, logp, which
// is the absolute value of the base-2 logarithm of the probability of a
// "1".
//
// https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.3.2
  int decodeSymbolLogP(int logp) {
    int k; // uint32 //nolint:varnamelen
    final scale = rangeSize >> logp;

    if (highAndCodedDifference >= scale) {
      highAndCodedDifference -= scale;
      rangeSize -= scale;
      k = 0;
    } else {
      rangeSize = scale;
      k = 1;
    }
    normalize();

    return k;
  }

// SetInternalValues is used when using the RangeDecoder when testing.
  void setInternalValues(
      Uint8List data, int bitsRead, int rangeSize, int highAndCodedDifference) {
    data = data;
    this.bitsRead = bitsRead;
    this.rangeSize = rangeSize;
    this.highAndCodedDifference = highAndCodedDifference;
  }

  num localMin(num a, num b) {
    if (a < b) {
      return a;
    }

    return b;
  }

// DecodeSymbolWithICDF decodes a single symbol
// with a table-based context of up to 8 bits.
//
// https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.3.3
  int DecodeSymbolWithICDF(List<int> cumulativeDistributionTable) {
    int k, scale, total, symbol, low, high; //nolint:varnamelen

    total = cumulativeDistributionTable[0]; //nolint:gosec // G115
    cumulativeDistributionTable = cumulativeDistributionTable.sublist(1);

    scale = (rangeSize / total).toInt();
    symbol = total -
        localMin(highAndCodedDifference / (rangeSize / total) + 1, total)
            .toInt(); //nolint:gosec // G115

    // nolint: revive
    for (k = 0; cumulativeDistributionTable[k] <= symbol; k++) {
      //nolint:gosec // G115
    }

    high = cumulativeDistributionTable[k]; //nolint:gosec // G115
    if (k != 0) {
      low = cumulativeDistributionTable[k - 1]; //nolint:gosec // G115
    } else {
      low = 0;
    }

    update(scale, low, high, total);

    return k;
  }
}

// minRangeSize is the minimum allowed size for rng.
// It's equal to math.Pow(2, 23).
const minRangeSize = 1 << 23;
