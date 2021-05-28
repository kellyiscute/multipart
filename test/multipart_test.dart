import 'dart:io';

import 'package:multipart/multipart.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() async {
  var server = await HttpServer.bind("localhost", 9000);
  print("running");
  test("description", () async {
    await for (var req in server) {
      Multipart multipart = Multipart(req);
      var loaded = await multipart.load();
      expect(loaded.length, equals(2));
      expect(loaded[0].field, "dfg");
    }
  });
}
