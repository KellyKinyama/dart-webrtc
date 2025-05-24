import '../bit_buffer.dart';

/// BitBuffer写入器，负责向BitBuffer中写入比特数据
class BitBufferWriter {
  /// 当前写入位置（以比特为单位）
  int _currentPosition = 0;

  /// 关联的 BitBuffer 对象，用于存储写入的比特数据
  final BitBuffer _buffer;

  /// 构造函数，初始化 BitBufferWriter 并关联指定的 BitBuffer
  BitBufferWriter(this._buffer);

  /// 跳过指定数量的比特位置（可正可负）
  void skip(int offset) {
    _currentPosition += offset;
  }

  /// 将写入位置设定为指定位置，必要时扩展缓冲区
  void seekTo(int newPosition) {
    _currentPosition = newPosition;
    int requiredExtraBits = _currentPosition - _buffer.bitLength;
    if (requiredExtraBits > 0) {
      _buffer.allocate(requiredExtraBits);
    }
  }

  /// 检查缓冲区是否有足够空间写入指定比特数，若不足则自动扩展
  void allocateIfNeeded(int bitsToWrite) {
    int targetPosition = _currentPosition + bitsToWrite;
    int extraBitsNeeded = targetPosition - _buffer.bitLength;
    if (extraBitsNeeded > 0) {
      _buffer.allocate(extraBitsNeeded);
    }
  }

  /// 写入一个布尔值，将 true 转换为 1，false 转换为 0
  void writeBool(bool value) {
    int bitValue = value ? 1 : 0;
    writeBit(bitValue);
  }

  /// 写入一个比特值（0或1）
  void writeBit(int value) {
    allocateIfNeeded(1); // 检查是否有1比特空间
    _buffer.writeBit(_currentPosition, value);
    _currentPosition += 1;
  }

  /// 写入一个有符号整数，使用指定的二进制位数和位序
  void writeInt(
    int value, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    allocateIfNeeded(binaryDigits);
    _buffer.writeInt(_currentPosition, value, binaryDigits: binaryDigits, order: order);
    _currentPosition += binaryDigits;
  }

  /// 写入一个有符号大整数，使用指定的二进制位数和位序
  void writeBigInt(
    BigInt value, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    allocateIfNeeded(binaryDigits);
    _buffer.writeBigInt(_currentPosition, value, binaryDigits: binaryDigits, order: order);
    _currentPosition += binaryDigits;
  }

  /// 写入一个无符号整数，使用指定的二进制位数和位序
  void writeUint(
    int value, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    allocateIfNeeded(binaryDigits);
    _buffer.writeUint(_currentPosition, value, binaryDigits: binaryDigits, order: order);
    _currentPosition += binaryDigits;
  }

  /// 写入一个无符号大整数，使用指定的二进制位数和位序
  void writeUBigInt(
    BigInt value, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    allocateIfNeeded(binaryDigits);
    _buffer.writeUBigInt(_currentPosition, value, binaryDigits: binaryDigits, order: order);
    _currentPosition += binaryDigits;
  }

  /// 写入一个整数列表，每个整数使用指定的二进制位数和位序
  void writeIntList(
    List<int> values, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    int totalBits = values.length * binaryDigits;
    allocateIfNeeded(totalBits);
    _buffer.writeIntList(_currentPosition, values, binaryDigits: binaryDigits, order: order);
    _currentPosition += totalBits;
  }

  /// 写入一个 UTF-8 编码的字符串，每个字符使用指定的二进制位数和位序
  void writeUtf8String(
    String value, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    int totalBits = value.length * binaryDigits;
    allocateIfNeeded(totalBits);
    _buffer.writeUtf8String(_currentPosition, value, binaryDigits: binaryDigits, order: order);
    _currentPosition += totalBits;
  }
}
