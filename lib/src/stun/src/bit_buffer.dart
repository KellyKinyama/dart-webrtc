import 'dart:typed_data';

class BitBufferWriter {
  final BitBuffer _bitBuffer;

  BitBufferWriter(this._bitBuffer);

  // Write an unsigned integer to the buffer
  void putUnsignedInt(int value, {required int binaryDigits}) {
    _bitBuffer.putUnsignedInt(value, binaryDigits: binaryDigits);
  }

  // Write an unsigned integer using a specific binary digit count
  void putUnsignedIntFromBuffer(int value, int binaryDigits) {
    _bitBuffer.putUnsignedInt(value, binaryDigits: binaryDigits);
  }

  // Write an individual bit to the buffer
  void putBit(bool bit) {
    _bitBuffer.putBit(bit ? 1 : 0);
  }

  // Write a byte (8 bits) to the buffer
  void putByte(int value) {
    _bitBuffer.putUnsignedInt(value, binaryDigits: 8);
  }

  // Write a short (16 bits) to the buffer
  void putShort(int value) {
    _bitBuffer.putUnsignedInt(value, binaryDigits: 16);
  }

  // Write an integer (32 bits) to the buffer
  void putInt(int value) {
    _bitBuffer.putUnsignedInt(value, binaryDigits: 32);
  }

  // Write a variable length string to the buffer
  void putString(String value) {
    final bytes = Uint8List.fromList(value.codeUnits);
    putUnsignedInt(bytes.length, binaryDigits: 16); // Store length
    for (int byte in bytes) {
      putByte(byte);
    }
  }
}

class BitBufferReader {
  final ByteData _data;
  int _position = 0;

  BitBufferReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  // Read an unsigned integer with a specific number of bits
  int getUnsignedInt({required int binaryDigits}) {
    int result = 0;
    for (int i = 0; i < binaryDigits; i++) {
      result <<= 1;
      result |= (getBit() ? 1 : 0);
    }
    return result;
  }

  // Read a bit from the buffer
  bool getBit() {
    if (_position >= _data.lengthInBytes * 8) {
      throw RangeError('Buffer underflow');
    }
    int byteIndex = _position ~/ 8;
    int bitIndex = _position % 8;
    _position++;
    return (_data.getUint8(byteIndex) & (1 << (7 - bitIndex))) != 0;
  }

  // Skip a number of bits
  void skipBits(int numBits) {
    _position += numBits;
    if (_position > _data.lengthInBytes * 8) {
      throw RangeError('Buffer underflow');
    }
  }

  // Read an unsigned integer of a specific length (in bytes)
  int getUnsignedInt32() {
    if (_position + 32 > _data.lengthInBytes * 8) {
      throw RangeError('Buffer underflow');
    }
    int value = _data.getUint32(_position ~/ 8, Endian.big);
    _position += 32;
    return value;
  }

  // Read an unsigned integer of 16 bits
  int getUnsignedInt16() {
    if (_position + 16 > _data.lengthInBytes * 8) {
      throw RangeError('Buffer underflow');
    }
    int value = _data.getUint16(_position ~/ 8, Endian.big);
    _position += 16;
    return value;
  }

  // Read a signed integer of 32 bits
  int getSignedInt32() {
    if (_position + 32 > _data.lengthInBytes * 8) {
      throw RangeError('Buffer underflow');
    }
    int value = _data.getInt32(_position ~/ 8, Endian.big);
    _position += 32;
    return value;
  }

  // Check if the reader has more data
  bool hasMore() {
    return _position < _data.lengthInBytes * 8;
  }

  // Get the current position in the buffer (in bits)
  int get position => _position;
}

class BitBuffer {
  final ByteData _data;
  int _bitOffset = 0;

  BitBuffer([int length = 64]) : _data = ByteData(length);

  int get length => _data.lengthInBytes * 8;

  int get bitOffset => _bitOffset;

  // Read unsigned integer from buffer
  int getUnsignedInt({required int binaryDigits}) {
    int result = 0;
    for (int i = 0; i < binaryDigits; i++) {
      result |= (getBit() << (binaryDigits - 1 - i));
    }
    return result;
  }

  // Read a single bit
  int getBit() {
    final byteIndex = _bitOffset ~/ 8;
    final bitIndex = _bitOffset % 8;
    final byteValue = _data.getUint8(byteIndex);
    _bitOffset++;
    return (byteValue >> (7 - bitIndex)) & 1;
  }

  // Write unsigned integer to buffer
  void putUnsignedInt(int value, {required int binaryDigits}) {
    for (int i = 0; i < binaryDigits; i++) {
      putBit((value >> (binaryDigits - 1 - i)) & 1);
    }
  }

  // Write a single bit to buffer
  void putBit(int bit) {
    final byteIndex = _bitOffset ~/ 8;
    final bitIndex = _bitOffset % 8;
    final currentByte = _data.getUint8(byteIndex);
    final newByte = currentByte | (bit << (7 - bitIndex));
    _data.setUint8(byteIndex, newByte);
    _bitOffset++;
  }

  // Convert to Uint8List
  Uint8List toUInt8List() {
    return _data.buffer.asUint8List();
  }

  // Reset bit offset
  void reset() {
    _bitOffset = 0;
  }
}

void main() {
  var bitBuffer = BitBuffer();

  // Example usage
  bitBuffer.putUnsignedInt(0x1234, binaryDigits: 16);
  bitBuffer.putBit(1); // Adding one more bit
  print(bitBuffer.toUInt8List()); // Output the buffer as bytes
}
