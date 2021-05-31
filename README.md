# multipart
A dart package for decoding multipart/form-data

## Usage  

```dart
Multipart multipart = Multipart([your httpRequest]);
var loaded = await multipart.load();
print(loaded.content.toBytes())
```
