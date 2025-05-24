import '../bit_buffer.dart';

/// BitBuffer读取器，负责从BitBuffer中顺序读取比特数据
class BitBufferReader {
  /// 当前读取位置（以比特为单位）
  int _currentPosition = 0;

  /// 获取当前读取位置
  int get position => _currentPosition;

  /// 关联的 BitBuffer 对象，用于读取比特数据
  final BitBuffer _buffer;

  /// 构造函数，初始化 BitBufferReader 并关联指定的 BitBuffer
  BitBufferReader(this._buffer);

  /// 获取剩余可读的比特数
  int get remaining => _buffer.bitLength - _currentPosition;

  /// 跳过指定数量的比特，更新当前读取位置
  void skip(int offset) {
    _currentPosition += offset;
  }

  /// 将读取位置设定到指定位置
  void seekTo(int position) {
    _currentPosition = position;
  }

  /// 从当前读取位置获取一个布尔值（true 或 false）
  bool readBool() {
    // 读取当前比特
    final int currentBit = readBit();
    return currentBit != 0;
  }

  /// 从当前读取位置获取一个比特，并更新读取位置
  int readBit() {
    // 获取当前位置的比特值
    final int bitValue = _buffer.readBit(_currentPosition);
    // 更新读取位置
    _currentPosition += 1;
    return bitValue;
  }

  /// 从当前读取位置读取一个有符号整数
  int readInt({
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 调用 BitBuffer 的 readInt 方法获取整数值
    final int signedInt = _buffer.readInt(_currentPosition, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += binaryDigits;
    return signedInt;
  }

  /// 从当前读取位置读取一个有符号大整数
  BigInt readBigInt({
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 调用 BitBuffer 的 readBigInt 方法获取大整数值
    final BigInt signedBigInt = _buffer.readBigInt(_currentPosition, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += binaryDigits;
    return signedBigInt;
  }

  /// 从当前读取位置读取一个无符号整数
  int readUint({
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 调用 BitBuffer 的 readUnsignedInt 方法获取无符号整数
    final int unsignedInt = _buffer.readUint(_currentPosition, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += binaryDigits;
    return unsignedInt;
  }

  /// 从当前读取位置读取一个无符号大整数
  BigInt readUBigInt({
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 调用 BitBuffer 的 readUnsignedBigInt 方法获取无符号大整数
    final BigInt unsignedBigInt = _buffer.readUBigInt(_currentPosition, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += binaryDigits;
    return unsignedBigInt;
  }

  /// 从当前读取位置读取指定数量的整数列表，每个整数占 binaryDigits 位
  List<int> readIntList(
    int size, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 读取整数列表
    final List<int> intList = _buffer.readIntList(_currentPosition, size, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += size;
    return intList;
  }

  /// 从当前读取位置读取一个 UTF-8 编码字符串，size 表示字节数
  String readUtf8String(
    int size, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 读取 UTF-8 字符串
    final String utf8String = _buffer.readUtf8String(_currentPosition, size, binaryDigits: binaryDigits, order: order);
    // 更新读取位置
    _currentPosition += size;
    return utf8String;
  }
}
