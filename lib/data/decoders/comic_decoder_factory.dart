import 'package:path/path.dart' as p;

import 'i_comic_decoder.dart';
import 'pdf_decoder.dart';
import 'rar_cbr_decoder.dart';
import 'zip_cbz_decoder.dart';

/// Desteklenen dosya uzantıları (büyük/küçük harf duyarsız).
const Set<String> supportedExtensions = {
  '.cbz',
  '.zip',
  '.cbr',
  '.rar',
  '.pdf',
};

/// Dosya uzantısına bakarak doğru [IComicDecoder] uygulamasını döner.
///
/// | Uzantı      | Decoder          | Arka plan kütüphanesi     |
/// |-------------|------------------|---------------------------|
/// | .cbz / .zip | [ZipCbzDecoder]  | package:archive (stable)  |
/// | .cbr / .rar | [RarCbrDecoder]  | koni_archive (pure Dart)  |
/// | .pdf        | [PdfDecoder]     | pdfx (native renderer)    |
class ComicDecoderFactory {
  ComicDecoderFactory._();

  /// [filePath] uzantısına göre doğru decoder'ı oluşturur.
  /// Bilinmeyen uzantı için [UnsupportedError] fırlatır.
  static IComicDecoder createForFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();

    return switch (ext) {
      '.cbz' || '.zip' => ZipCbzDecoder(filePath),
      '.cbr' || '.rar' => RarCbrDecoder(filePath),
      '.pdf' => PdfDecoder(filePath),
      _ => throw UnsupportedError(
          'Desteklenmeyen format: $ext\n'
          'Desteklenen formatlar: ${supportedExtensions.join(', ')}',
        ),
    };
  }

  /// [filePath] uzantısının desteklenip desteklenmediğini döner.
  static bool isSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return supportedExtensions.contains(ext);
  }
}
