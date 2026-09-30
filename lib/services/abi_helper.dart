/// Resolves to native (dart:ffi) on Android/desktop,
/// and to the web stub on web builds.
library;

export 'abi_helper_stub.dart'
    if (dart.library.ffi) 'abi_helper_native.dart';
