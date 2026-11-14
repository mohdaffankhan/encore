import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Windows' Data Protection API (what browsers keep saved passwords with):
// data encrypted for this Windows user, readable only when signed in as
// them, on this PC.

final class _Blob extends Struct {
  @Uint32()
  external int size;
  external Pointer<Uint8> data;
}

typedef _ProtectC = Int32 Function(
  Pointer<_Blob> dataIn,
  Pointer<Utf16> description,
  Pointer<_Blob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_Blob> dataOut,
);
typedef _Protect = int Function(
  Pointer<_Blob> dataIn,
  Pointer<Utf16> description,
  Pointer<_Blob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_Blob> dataOut,
);
typedef _UnprotectC = Int32 Function(
  Pointer<_Blob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_Blob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_Blob> dataOut,
);
typedef _Unprotect = int Function(
  Pointer<_Blob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_Blob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_Blob> dataOut,
);

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _protect = _crypt32.lookupFunction<_ProtectC, _Protect>(
  'CryptProtectData',
);
final _unprotect = _crypt32.lookupFunction<_UnprotectC, _Unprotect>(
  'CryptUnprotectData',
);
final _localFree = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');

/// No UI: fail rather than ask the user anything.
const _uiForbidden = 0x1;

/// Something to tell Encore's data apart from other apps' (not a secret).
final _entropy = Uint8List.fromList('Encore YouTube Music sign-in'.codeUnits);

Uint8List protect(Uint8List data) => _call(data, encrypt: true);

/// Throws if [data] wasn't protected by this Windows user (or was changed).
Uint8List unprotect(Uint8List data) => _call(data, encrypt: false);

Uint8List _call(Uint8List data, {required bool encrypt}) {
  return using((arena) {
    Pointer<_Blob> blob(Uint8List bytes) {
      final b = arena<_Blob>();
      final p = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      p.asTypedList(bytes.length).setAll(0, bytes);
      b.ref
        ..size = bytes.length
        ..data = p;
      return b;
    }

    final input = blob(data);
    final entropy = blob(_entropy);
    final output = arena<_Blob>();
    final ok = encrypt
        ? _protect(
            input,
            nullptr,
            entropy,
            nullptr,
            nullptr,
            _uiForbidden,
            output,
          )
        : _unprotect(
            input,
            nullptr,
            entropy,
            nullptr,
            nullptr,
            _uiForbidden,
            output,
          );
    if (ok == 0) {
      throw StateError(encrypt ? 'Encrypting failed' : 'Decrypting failed');
    }
    try {
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.size));
    } finally {
      _localFree(output.ref.data.cast());
    }
  });
}
