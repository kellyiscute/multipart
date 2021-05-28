import 'dart:io';
import 'dart:math';

import 'package:multipart/multipart.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() async {
  var server = await HttpServer.bind("localhost", 9000);
  await for (var req in server) {
    Multipart multipart = Multipart(req);
    var loaded = await multipart.load();
    exit(0);
    // expect(loaded.length, equals(2));
    // expect(loaded[0].field, "阿斯顿发");
  }
  // test("description", () async {
  // });
}
