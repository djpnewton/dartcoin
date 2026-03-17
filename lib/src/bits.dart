import 'dart:typed_data';

class BitsWriter {
  final List<bool> _bits = [];

  void clear() {
    _bits.clear();
  }

  void writeBit(bool bit) {
    _bits.add(bit);
  }

  void writeBits(BigInt value, int count) {
    for (int i = count - 1; i >= 0; i--) {
      _bits.add((value & (BigInt.one << i)) != BigInt.zero);
    }
  }

  @override
  String toString() {
    return _bits.map((b) => b ? '1' : '0').join('');
  }

  Uint8List toBytes() {
    final byteCount = (_bits.length + 7) ~/ 8;
    final bytes = Uint8List(byteCount);
    for (int i = 0; i < _bits.length; i++) {
      if (_bits[i]) {
        bytes[i ~/ 8] |= (1 << (7 - (i % 8)));
      }
    }
    return bytes;
  }
}

class BitsReader {
  final Uint8List _data;
  int _bitIndex = 0;

  BitsReader(this._data);

  @override
  String toString() {
    return _data
        .map((b) => b.toRadixString(2).padLeft(8, '0'))
        .join('')
        .substring(_data.length * 8 - remainingBits());
  }

  int remainingBits() {
    return _data.length * 8 - _bitIndex;
  }

  bool readBit() {
    if (_bitIndex >= _data.length * 8) {
      throw RangeError('No more bits to read');
    }
    final byteIndex = _bitIndex ~/ 8;
    final bitOffset = 7 - (_bitIndex % 8);
    final bit = (_data[byteIndex] & (1 << bitOffset)) != 0;
    _bitIndex++;
    return bit;
  }

  int readBits(int count) {
    if (count < 0 || count > 32) {
      throw ArgumentError('Count must be between 0 and 32');
    }
    if (remainingBits() < count) {
      throw RangeError('Not enough bits to read');
    }
    int value = 0;
    for (int i = 0; i < count; i++) {
      value <<= 1;
      value |= readBit() ? 1 : 0;
    }
    return value;
  }
}
