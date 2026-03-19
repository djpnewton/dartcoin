import 'dart:collection';
import 'dart:typed_data';

/// A fixed-length [List] whose elements are parsed from a contiguous byte
/// buffer on demand.
///
/// Elements are accessed by index; the byte offset of each element is computed
/// incrementally because each element's size is only known after parsing it.
/// Once parsed, elements are cached so they are never constructed twice.
///
/// [parse] constructs a [T] from a [Uint8List] starting at byte 0.
/// [sizeOf] returns the serialised byte length of an already-parsed [T],
/// which is used to advance to the next element's offset.
class LazyList<T> extends ListBase<T> {
  /// The raw bytes backing this list.
  final Uint8List bytes;

  final int _count;
  final T Function(Uint8List) _parse;
  final int Function(T) _sizeOf;

  /// _offsets[i] is the byte offset within [bytes] where element i starts.
  /// Populated incrementally; always contains at least [firstOffset].
  final List<int> _offsets;
  final List<T?> _cache;

  LazyList({
    required this.bytes,
    required int count,
    required int firstOffset,
    required T Function(Uint8List) parse,
    required int Function(T) sizeOf,
  }) : _count = count,
       _parse = parse,
       _sizeOf = sizeOf,
       _offsets = [firstOffset],
       _cache = List.filled(count, null);

  @override
  int get length => _count;

  @override
  set length(int _) =>
      throw UnsupportedError('Cannot change the length of a LazyList');

  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this);
    _scanTo(index);
    return _cache[index] ??= _parse(bytes.sublist(_offsets[index]));
  }

  @override
  void operator []=(int index, T value) {
    RangeError.checkValidIndex(index, this);
    _cache[index] = value;
  }

  /// Ensures [_offsets[i]] is known for all [i <= need], parsing and caching
  /// intermediate elements only as needed to advance the offset cursor.
  void _scanTo(int need) {
    while (_offsets.length <= need) {
      final i = _offsets.length - 1;
      final element = _cache[i] ??= _parse(bytes.sublist(_offsets[i]));
      _offsets.add(_offsets[i] + _sizeOf(element));
    }
  }
}
