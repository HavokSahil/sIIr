import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Owned by the analysis isolate. Kernels and aligned FFT buffers stay warm.
class NativeCqt implements Finalizable {
  late final NativeFinalizer _finalizer;
  late final DynamicLibrary _library;
  late final Pointer<Void> _context;
  late final Float32List _input;
  late final Pointer<Float> Function(Pointer<Void>) _run;
  late final void Function(Pointer<Void>) _destroy;
  NativeCqt() {
    _library = DynamicLibrary.open(
      Platform.environment['SHIRR_ECQT_LIBRARY'] ?? 'libshirr_ecqt.so',
    );
    _context =
        _library
            .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
              'shirr_cqt_create',
            )();
    if (_context == nullptr) throw StateError('ECQT initialization failed');
    final length = _library.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('shirr_cqt_length')(_context);
    _input = _library
        .lookupFunction<
          Pointer<Float> Function(Pointer<Void>),
          Pointer<Float> Function(Pointer<Void>)
        >('shirr_cqt_input')(_context)
        .asTypedList(length);
    _run = _library.lookupFunction<
      Pointer<Float> Function(Pointer<Void>),
      Pointer<Float> Function(Pointer<Void>)
    >('shirr_cqt_run');
    _finalizer = NativeFinalizer(
      _library.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'shirr_cqt_destroy',
      ),
    );
    _finalizer.attach(this, _context, detach: this);
    _destroy = _library.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('shirr_cqt_destroy');
  }
  List<double> transform(List<double> samples, int center) {
    // Kernels are left-aligned; center the longest window on the cursor.
    final start = center - _input.length ~/ 2;
    for (int i = 0; i < _input.length; i++) {
      final j = start + i;
      _input[i] = j >= 0 && j < samples.length ? samples[j] : 0;
    }
    final output = _run(_context);
    if (output == nullptr) throw StateError('ECQT transform failed');
    return List<double>.from(output.asTypedList(84));
  }

  void dispose() {
    _finalizer.detach(this);
    _destroy(_context);
  }
}
