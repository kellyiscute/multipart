import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bytes_io/bytes_io.dart';
import 'package:multipart/src/cached_bytes_builder.dart';

/// input --------------
///           pipe      \
///                    cache
class _BoundaryFinderPipe {
  List<int> pipe = [];
  Uint8List cached = Uint8List(1048576); // 1MB as a chunk
  int position = 0;
  String boundary;
  final int newLineChar = "\n".codeUnitAt(0);
  final int reternChar = "\r".codeUnitAt(0);
  final Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
  final CachedBytesBuilder cachedBytesBuilder = CachedBytesBuilder();
  final Future<void> Function(Uint8List, CachedBytesBuilder)
      boundaryReachedCallback;
  final BytesBuilder headerBytes = BytesBuilder();
  bool findHeaders = false;

  _BoundaryFinderPipe(String boundary, this.boundaryReachedCallback)
      : this.boundary = "--" + boundary + "\r\n";

  Future<void> put(int value) async {
    if (findHeaders) {
      if (pipe.length > 3) {
        pipe.removeAt(0);
      }
      pipe.add(value);
      if (pipe.length == 4 &&
          pipe.where((e) => e == newLineChar || e == reternChar).length == 4) {
        headerBytes.add(pipe);
        pipe.clear();
        findHeaders = false;
      }
    } else {
      pipe.add(value);
      if (pipe.length > this.boundary.length) {
        cached[position] = pipe[0];
        position++;
        pipe.removeAt(0);
      }
      // cache size       ⬇️
      if (position == 1048575) {
        await cachedBytesBuilder.add(cached);
        position = 0;
      }
      // statistically if the first and the last char matches
      // it likely is the boundary
      // no data supported!
      // number 45 ==> "-"
      if (pipe.take(2).where((e) => e == 45).length == 2 &&
          pipe.last == newLineChar) {
        if (decoder.convert(pipe) == boundary) {
          // push all cached bytes
          await cachedBytesBuilder.add(cached.getRange(0, position).toList());
          await this.boundaryReachedCallback(
              headerBytes.toBytes(), cachedBytesBuilder);
          cached.fillRange(0, cached.length, 0);
          headerBytes.clear();
          pipe.clear();
          findHeaders = true;
        }
      }
    }
  }
}

class MultipartContent {
  final String field;
  final String? filename;
  final CachedBytesBuilder content;
  final String? contentType;

  MultipartContent({
    required this.field,
    this.filename,
    required this.content,
    this.contentType,
  });
}

class Multipart {
  final HttpRequest request;
  late final String boundary;
  int _boundaryFound = 0;
  List<MultipartContent> content = [];

  Multipart(this.request) {
    if (request.headers.contentType == null) {
      throw Exception("content-type not present in headers");
    }
    if (request.headers.contentType!.mimeType != "multipart/form-data") {
      throw Exception("Damn it! Not a multipart");
    }
    assert(
      request.headers.contentType!.parameters.containsKey("boundary"),
      "malformed multipart",
    );
    boundary = request.headers.contentType!.parameters["boundary"]!;
  }

  Future<void> call() async {
    await load();
  }

  Future<void> _onBoundaryReached(
      Uint8List headerBytes, CachedBytesBuilder data) async {
    if (_boundaryFound == 0) {
      _boundaryFound++;
      return;
    }

    var headers = getFormDataHeader(headerBytes);
    MultipartContent content = MultipartContent(
      field: headers["name"]!,
      content: data,
      filename: headers["filename"],
      contentType: headers["content-type"],
    );
    this.content.add(content);
  }

  Future<List<MultipartContent>> load() async {
    final _BoundaryFinderPipe pipe =
        _BoundaryFinderPipe(boundary, _onBoundaryReached);

    await for (var data in request) {
      BytesReader reader = BytesReader.fromUint8List(data);
      while (reader.position < reader.data.length) {
        await pipe.put(reader.readByte());
      }
    }
    return content;
  }

  Map<String, String> getFormDataHeader(Uint8List data) {
    BytesReader reader = BytesReader.fromUint8List(data);
    String line;
    // group(1) => key, group(4) => value
    RegExp pattern = RegExp(r"([A-z-]*)((:\s)|=)([^;$]*)(;|$)");
    Utf8Decoder decoder = Utf8Decoder();
    Map<String, String> params = {};
    Uint8List r;
    do {
      r = reader.readUntil("\n".codeUnitAt(0));
      // dispose the '\n'
      reader.readByte();
      print(data);
      line = decoder.convert(r);
      params.addAll(
        Map.fromEntries(
          pattern.allMatches(line).map<MapEntry<String, String>>(
                (e) => MapEntry(e.group(1).toString(), e.group(4).toString()),
              ),
        ),
      );
    } while (r.isNotEmpty);
    return params;
  }
}
