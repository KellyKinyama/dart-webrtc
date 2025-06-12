// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// Package rangecoding provides a Range coder for the Opus bitstream.

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
class RangeDecoder {
  List<int> _data;
  int _bitsRead;

  int _rangeSize; // rng in RFC 6716, corresponds to uint32
  int _highAndCodedDifference; // val in RFC 6716, corresponds to uint32

  // minRangeSize is the minimum allowed size for rng.
  // It's equal to math.Pow(2, 23).
  static const int _minRangeSize = 1 << 23;

  RangeDecoder()
      : _data = [],
        _bitsRead = 0,
        _rangeSize = 128,
        _highAndCodedDifference = 0;

  /// Initializes the state of the Decoder.
  /// Let b0 be an 8-bit unsigned integer containing first input byte (or
  /// containing zero if there are no bytes in this Opus frame).  The
  /// decoder initializes rng to 128 and initializes val to (127 -
  /// (b0>>1)), where (b0>>1) is the top 7 bits of the first input byte.
  /// It saves the remaining bit, (b0&1), for use in the renormalization
  /// procedure described in Section 4.1.2.1, which the decoder invokes
  /// immediately after initialization to read additional bits and
  /// establish the invariant that rng > 2**23.
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.1
  void init(List<int> data) {
    _data = data;
    _bitsRead = 0;

    _rangeSize = 128;
    _highAndCodedDifference = 127 - _getBits(7);
    _normalize();
  }

  /// Decodes a single symbol with a table-based context of up to 8 bits.
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.3.3
  int decodeSymbolWithICDF(List<int> cumulativeDistributionTable) {
    int k;
    int scale;
    int total;
    int symbol;
    int low;
    int high;

    total = cumulativeDistributionTable[0];
    final actualCdf = cumulativeDistributionTable.sublist(1);

    scale = (_rangeSize ~/ total);
    symbol = (_highAndCodedDifference ~/ scale) + 1;
    symbol = total - localMin(symbol, total);

    // Find k such that actualCdf[k] <= symbol < actualCdf[k+1]
    k = 0;
    while (k < actualCdf.length && actualCdf[k] <= symbol) {
      k++;
    }

    high = actualCdf[k];
    if (k != 0) {
      low = actualCdf[k - 1];
    } else {
      low = 0;
    }

    _update(scale, low, high, total);

    return k;
  }

  /// Decodes a single binary symbol.
  /// The context is described by a single parameter, logp, which
  /// is the absolute value of the base-2 logarithm of the probability of a "1".
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.3.2
  int decodeSymbolLogP(int logp) {
    int k;
    final scale = _rangeSize >> logp;

    if (_highAndCodedDifference >= scale) {
      _highAndCodedDifference -= scale;
      _rangeSize -= scale;
      k = 0;
    } else {
      _rangeSize = scale;
      k = 1;
    }
    _normalize();

    return k;
  }

  /// Reads a single bit from the data stream.
  int _getBit() {
    final index = _bitsRead ~/ 8;
    final offset = _bitsRead % 8;

    if (index >= _data.length) {
      return 0; // Return 0 if out of bounds, as per Go's behavior
    }

    _bitsRead++;

    // Shift to get the bit at the correct position (MSB first)
    return (_data[index] >> (7 - offset)) & 1;
  }

  /// Reads [n] bits from the data stream.
  int _getBits(int n) {
    int bits = 0;

    for (int i = 0; i < n; i++) {
      if (i != 0) {
        bits <<= 1;
      }
      bits |= _getBit();
    }
    return bits;
  }

  /// Normalizes the range decoder state.
  /// To normalize the range, the decoder repeats the following process,
  /// implemented by ec_dec_normalize() (entdec.c), until rng > 2**23.  If
  /// rng is already greater than 2**23, the entire process is skipped.
  /// First, it sets rng to (rng<<8).  Then, it reads the next byte of the
  /// Opus frame and forms an 8-bit value sym, using the leftover bit
  /// buffered from the previous byte as the high bit and the top 7 bits of
  /// the byte just read as the other 7 bits of sym.  The remaining bit in
  /// the byte just read is buffered for use in the next iteration.  If no
  /// more input bytes remain, it uses zero bits instead.  See
  /// Section 4.1.1 for the initialization used to process the first byte.
  /// Then, it sets
  /// val = ((val<<8) + (255-sym)) & 0x7FFFFFFF
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.2.1
  void _normalize() {
    while (_rangeSize <= _minRangeSize) {
      _rangeSize <<= 8;
      // Go's (val<<8) + (255 - sym) could exceed 32 bits, then truncated by & 0x7FFFFFFF
      // Dart's ints handle arbitrary precision, so explicit mask is needed for consistency
      // with 32-bit unsigned arithmetic.
      _highAndCodedDifference =
          ((_highAndCodedDifference << 8) + (255 - _getBits(8))) & 0x7FFFFFFF;
    }
  }

  /// Updates the range decoder state after decoding a symbol.
  void _update(int scale, int low, int high, int total) {
    _highAndCodedDifference -= scale * (total - high);
    if (low != 0) {
      _rangeSize = scale * (high - low);
    } else {
      _rangeSize -= scale * (total - high);
    }

    _normalize();
  }

  // Helper function to find the minimum of two integers.
  // Go's `localMin` is for `uint`, but Dart's `int` suffices here.
  int localMin(int a, int b) {
    return a < b ? a : b;
  }

  /// Sets internal values, primarily for testing purposes.
  void setInternalValues(
      List<int> data, int bitsRead, int rangeSize, int highAndCodedDifference) {
    _data = data;
    _bitsRead = bitsRead;
    _rangeSize = rangeSize;
    _highAndCodedDifference = highAndCodedDifference;
  }
}
