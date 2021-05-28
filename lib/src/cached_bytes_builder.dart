import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:nanoid/async.dart';
import 'package:path/path.dart' as path;

class CachedBytesBuilder {
  int cachingSize = 10485760; // 10MB
  File? _cacheFile;
  int _length = 0;
  final List<Uint8List> _chunks = [];

  bool get isCached => _cacheFile != null;
  Future<String> text() async => Utf8Decoder().convert(await toBytes());
  Future<dynamic> json() async => jsonDecode((await text()));

  CachedBytesBuilder({int? cacheStart}) {
    if (cacheStart != null) {
      cachingSize = cacheStart;
    }
  }

  Future<void> add(List<int> bytes) async {
    Uint8List typedBytes;
    if (bytes is Uint8List) {
      typedBytes = bytes;
    } else {
      typedBytes = Uint8List.fromList(bytes);
    }
    _length += typedBytes.length;

    if (_cacheFile != null) {
      this._cacheFile = await _cacheFile!
          .writeAsBytes(bytes, mode: FileMode.append, flush: true);
      return;
    }

    if (_length > cachingSize) {
      _cacheFile = File.fromUri(Uri.parse(
          path.join(Directory.systemTemp.path, await nanoid(16) + ".cache")));

      _cacheFile = await _cacheFile!.writeAsBytes(await this.takeBytes());
      _cacheFile = await _cacheFile!.writeAsBytes(typedBytes);
      return;
    }
    _chunks.add(typedBytes);
  }

  Future<void> addByte(int byte) async {
    _length++;
    if (_cacheFile != null) {
      _cacheFile = await _cacheFile!.writeAsBytes([byte]);
      return;
    }
    _chunks.add(Uint8List(1)..[0] = byte);
  }

  Future<Uint8List> takeBytes() async {
    if (_cacheFile != null) {
      var data = await _cacheFile!.readAsBytes();
      await _cacheFile!.delete();
      return data;
    }

    if (_length == 0) return Uint8List(0);
    if (_chunks.length == 1) {
      var buffer = _chunks[0];
      _clear();
      return buffer;
    }
    var buffer = Uint8List(_length);
    int offset = 0;
    for (var chunk in _chunks) {
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _clear();
    return buffer;
  }

  Future<Uint8List> toBytes() async {
    if (_cacheFile != null) {
      return _cacheFile!.readAsBytes();
    }

    if (_length == 0) return Uint8List(0);
    var buffer = Uint8List(_length);
    int offset = 0;
    for (var chunk in _chunks) {
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return buffer;
  }

  Future<void> save(Uri path) async {
    if (_cacheFile != null) {
      await _cacheFile!.rename(_cacheFile!.uri.resolveUri(path).path);
    }
    await File.fromUri(path).writeAsBytes(await this.takeBytes());
  }

  Future<Uint8List> readBytes(int length) async {
    BytesBuilder builder = BytesBuilder();
    if (isCached) {
      await for (var data in this._cacheFile!.openRead().take(length)) {
        builder.add(data);
      }
      return builder.toBytes();
    } else {
      int pos = 0;
      while (builder.length < length) {
        int remaining = length - builder.length;
        if (_chunks[pos].lengthInBytes > remaining) {
          builder.add(_chunks[pos].getRange(0, remaining).toList());
        } else {
          builder.add(_chunks[pos]);
        }
      }
    }
    return builder.toBytes();
  }

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  Future<void> clear() async {
    await _clear();
  }

  Future<void> _clear() async {
    if (_cacheFile != null) {
      await _cacheFile!.delete();
      return;
    }
    _length = 0;
    _chunks.clear();
  }
}
