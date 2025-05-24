import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../bit_buffer.dart';

/// 比特操作缓冲区
class BitBuffer {
  /// 内部存储单元列表，每个元素为一个存储单元
  final List<int> _words = [];

  /// 已使用比特数
  int _bitLength = 0;

  /// 获取已使用比特数
  int get bitLength => _bitLength;

  /// 地址位数，用于计算存储单元大小
  final int _addressBits = 6;

  /// 每个存储单元包含的比特数，等于 2^_addressBits
  late final int _wordSize = 1 << _addressBits;

  /// 存储单元内比特索引掩码
  late final int _bitIndexMask = _wordSize - 1;

  BitBuffer();

  /// 从 Uint8List 构造 BitBuffer
  factory BitBuffer.fromUint8List(
    Uint8List data, {
    BitOrder order = BitOrder.MSBFirst,
  }) =>
      BitBuffer.fromUintList(data, binaryDigits: 8, order: order);

  /// 转换为 Uint8List
  Uint8List toUint8List({BitOrder order = BitOrder.MSBFirst}) {
    final List<int> byteList = [];
    final BitBufferReader reader = getReader();
    while (reader.remaining > 0) {
      final int byteValue = reader.readUint(binaryDigits: 8, order: order);
      byteList.add(byteValue);
    }
    return Uint8List.fromList(byteList);
  }

  /// 从无符号整数列表构造 BitBuffer
  factory BitBuffer.fromUintList(
    List<int> data, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final BitBuffer buffer = BitBuffer();
    final BitBufferWriter writer = buffer.getWriter();
    for (final int unsignedValue in data) {
      writer.writeUint(unsignedValue, binaryDigits: binaryDigits, order: order);
    }
    return buffer;
  }

  /// 转换为无符号整数列表
  List<int> toUintList({
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final List<int> unsignedList = [];
    final BitBufferReader reader = getReader();
    while (reader.remaining > 0) {
      final int unsignedValue =
          reader.readUint(binaryDigits: binaryDigits, order: order);
      unsignedList.add(unsignedValue);
    }
    return unsignedList;
  }

  /// 从有符号整数列表构造 BitBuffer
  factory BitBuffer.fromIntList(
    List<int> data, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final BitBuffer buffer = BitBuffer();
    final BitBufferWriter writer = buffer.getWriter();
    for (final int signedValue in data) {
      writer.writeInt(signedValue, binaryDigits: binaryDigits, order: order);
    }
    return buffer;
  }

  /// 转换为有符号整数列表
  List<int> toIntList({
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final List<int> intList = [];
    final BitBufferReader reader = getReader();
    while (reader.remaining > 0) {
      final int intValue =
          reader.readInt(binaryDigits: binaryDigits, order: order);
      intList.add(intValue);
    }
    return intList;
  }

  /// 获取 BitBuffer 读取器
  BitBufferReader getReader() => BitBufferReader(this);

  /// 获取 BitBuffer 写入器
  BitBufferWriter getWriter() => BitBufferWriter(this);

  /// 获取追加写入器，其写入位置设为当前末尾
  BitBufferWriter append() => getWriter()..seekTo(_bitLength);

  /// 分配指定比特容量，必要时扩展存储单元
  void allocate(int capacity) {
    // 当前存储单元剩余可用比特数
    int totalAllocatedBits = _words.length * _wordSize;
    int freeBits = totalAllocatedBits - _bitLength;
    if (freeBits > 0) {
      // 使用剩余空闲比特
      _bitLength += freeBits;
      capacity -= freeBits;
    }
    while (capacity > 0) {
      _bitLength += min(capacity, _wordSize);
      capacity = max(capacity - _wordSize, 0);
      _words.add(0);
    }
    _bitLength += capacity;
  }

  /// 移除多余的存储单元以节约内存
  void trim() {
    int totalAllocatedBits = _words.length * _wordSize;
    int freeBits = totalAllocatedBits - _bitLength;
    // 只移除完全未使用的存储单元
    while (freeBits >= _wordSize) {
      _words.removeLast();
      totalAllocatedBits = _words.length * _wordSize;
      freeBits = totalAllocatedBits - _bitLength;
    }
  }

  @override
  String toString() => toSectionString(0, _bitLength);

  /// 获取指定范围内的比特字符串表示
  String toSectionString(int start, int length) {
    final int end = min(start + length, _bitLength);
    final StringBuffer buffer = StringBuffer();
    for (int currentPos = start; currentPos < end; currentPos++) {
      final int bitValue = readBit(currentPos);
      buffer.write(bitValue);
    }
    return buffer.toString();
  }

  /// 获取指定位置的比特值（0或1）
  int readBit(int position) {
    if (position < 0 || position >= _bitLength) {
      throw RangeError('position $position 超出范围，当前长度为 $_bitLength');
    }
    // 计算所属存储单元索引
    final int wordIndex = position >> _addressBits;
    // 计算在存储单元内的比特索引
    final int bitIndex = position & _bitIndexMask;
    // 获取存储单元数据
    final int wordData = _words[wordIndex];
    // 提取目标比特
    final int shiftedData = wordData >> bitIndex;
    final int bitValue = shiftedData & 1;
    return bitValue;
  }

  /// 设置指定位置的比特值
  void writeBit(int position, int bit) {
    if (position < 0 || position >= _bitLength) {
      throw RangeError('position $position 超出范围，当前长度为 $_bitLength');
    }
    final int wordIndex = position >> _addressBits;
    final int bitIndex = position & _bitIndexMask;
    int currentWord = _words[wordIndex];
    if (bit == 0) {
      // 清除指定位
      final int clearMask = ~(1 << bitIndex);
      currentWord = currentWord & clearMask;
    } else {
      // 设置指定位
      final int setMask = 1 << bitIndex;
      currentWord = currentWord | setMask;
    }
    _words[wordIndex] = currentWord;
  }

  /// 读取指定偏移位置的有符号整数
  int readInt(
    int offset, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    // 先读取无符号整数
    final int unsignedValue =
        readUint(offset, binaryDigits: binaryDigits, order: order);
    // 检查符号位
    final int signBit = (unsignedValue >> (binaryDigits - 1)) & 1;
    if (signBit == 0) {
      return unsignedValue;
    }
    // 若为负数，根据补码还原
    final int fullMask = (1 << binaryDigits) - 1;
    final int inverted = ~(unsignedValue - 1) & fullMask;
    final int signedValue = -inverted;
    return signedValue;
  }

  /// 写入指定偏移位置的有符号整数
  void writeInt(
    int offset,
    int value, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    int writeValue = value;
    if (writeValue.isNegative) {
      final int fullMask = (1 << binaryDigits) - 1;
      final int absValue = -writeValue;
      final int complement = (~absValue + 1) & fullMask;
      writeValue = complement;
    }
    writeUint(offset, writeValue, binaryDigits: binaryDigits, order: order);
  }

  /// 读取指定偏移位置的无符号整数
  int readUint(
    int offset, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    int result = 0;
    for (int i = 0; i < binaryDigits; i++) {
      int actualPosition;
      if (order == BitOrder.MSBFirst) {
        actualPosition = offset + i;
      } else {
        actualPosition = offset + binaryDigits - 1 - i;
      }
      final int currentBit = readBit(actualPosition);
      final int shiftAmount = binaryDigits - 1 - i;
      result |= currentBit << shiftAmount;
    }
    return result;
  }

  /// 写入指定偏移位置的无符号整数
  void writeUint(
    int offset,
    int value, {
    int binaryDigits = 64,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    for (int i = 0; i < binaryDigits; i++) {
      final int extractedBit = (value >> i) & 1;
      int targetPosition;
      if (order == BitOrder.MSBFirst) {
        targetPosition = offset + binaryDigits - 1 - i;
      } else {
        targetPosition = offset + i;
      }
      writeBit(targetPosition, extractedBit);
    }
  }

  /// 读取指定偏移位置的有符号大整数
  BigInt readBigInt(
    int offset, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final BigInt unsignedBigInt =
        readUBigInt(offset, binaryDigits: binaryDigits, order: order);
    final BigInt signIndicator = unsignedBigInt >> (binaryDigits - 1);
    if (signIndicator == BigInt.zero) {
      return unsignedBigInt;
    }
    final BigInt fullMask = (BigInt.one << binaryDigits) - BigInt.one;
    final BigInt inverted = (~(unsignedBigInt - BigInt.one)) & fullMask;
    return -inverted;
  }

  /// 写入指定偏移位置的有符号大整数
  void writeBigInt(
    int offset,
    BigInt value, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    BigInt writeValue = value;
    if (writeValue.isNegative) {
      final BigInt fullMask = (BigInt.one << binaryDigits) - BigInt.one;
      final BigInt absValue = -writeValue;
      final BigInt complement = ((~absValue) + BigInt.one) & fullMask;
      writeValue = complement;
    }
    writeUBigInt(offset, writeValue, binaryDigits: binaryDigits, order: order);
  }

  /// 读取指定偏移位置的无符号大整数
  BigInt readUBigInt(
    int offset, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < binaryDigits; i++) {
      int actualPosition;
      if (order == BitOrder.MSBFirst) {
        actualPosition = offset + i;
      } else {
        actualPosition = offset + binaryDigits - 1 - i;
      }
      final int currentBit = readBit(actualPosition);
      final int shiftAmount = binaryDigits - 1 - i;
      result |= BigInt.from(currentBit) << shiftAmount;
    }
    return result;
  }

  /// 写入指定偏移位置的无符号大整数
  void writeUBigInt(
    int offset,
    BigInt value, {
    int binaryDigits = 128,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    for (int i = 0; i < binaryDigits; i++) {
      final BigInt extractedBit = (value >> i) & BigInt.one;
      int targetPosition;
      if (order == BitOrder.MSBFirst) {
        targetPosition = offset + binaryDigits - 1 - i;
      } else {
        targetPosition = offset + i;
      }
      writeBit(targetPosition, extractedBit.toInt());
    }
  }

  /// 读取从指定偏移开始的整数列表，每个整数占 binaryDigits 位
  List<int> readIntList(
    int offset,
    int size, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final List<int> intList = [];
    for (int currentOffset = 0;
        currentOffset < size;
        currentOffset += binaryDigits) {
      final int intValue = readInt(offset + currentOffset,
          binaryDigits: binaryDigits, order: order);
      intList.add(intValue);
    }
    return intList;
  }

  /// 写入整数列表，每个整数占 binaryDigits 位
  void writeIntList(
    int offset,
    List<int> values, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    int currentOffset = offset;
    for (final int intValue in values) {
      writeInt(currentOffset, intValue,
          binaryDigits: binaryDigits, order: order);
      currentOffset += binaryDigits;
    }
  }

  /// 读取指定偏移位置的 UTF-8 编码字符串（size 字节）
  String readUtf8String(
    int offset,
    int size, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final List<int> byteList =
        readIntList(offset, size, binaryDigits: binaryDigits, order: order);
    return utf8.decode(byteList);
  }

  /// 写入 UTF-8 编码字符串
  void writeUtf8String(
    int offset,
    String value, {
    int binaryDigits = 8,
    BitOrder order = BitOrder.MSBFirst,
  }) {
    final List<int> utf8Bytes = utf8.encode(value);
    writeIntList(offset, utf8Bytes, binaryDigits: binaryDigits, order: order);
  }

  void clear() {
    _words.clear();
    _bitLength = 0;
  }
}
