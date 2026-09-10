import "dart:convert" show utf8;
import "dart:developer" show log;
import "dart:io" show Directory, File, FileSystemException;
import "dart:typed_data" show Uint8List;

import "package:crypto/crypto.dart" show sha256;
import "package:path_provider/path_provider.dart" show getTemporaryDirectory;

class ImageUtil {
  // todo: maxCacheCount or maxCacheSize 도입
  static final Map<String, String> _hashPathMap = {};

  static Future<String> saveImage(Uint8List bytes, [String? cacheKey]) async {
    final key = cacheKey ?? _generateImageHashFromBytes(bytes);
    late final String path;
    if (_hashPathMap.containsKey(key)) {
      path = _hashPathMap[key]!;
      log("이미 저장된 이미지입니다. 저장된 path를 반환합니다. $path", name: "ImageSaveUtil");
    } else {
      path = await _makeFile(key, bytes);
      _hashPathMap[key] = path;
    }
    return path;
  }

  /* ----- Hashing ----- */

  static String _generateImageHashFromBytes(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /* ----- File ----- */

  static Future<String> _makeFile(String key, Uint8List bytes) async {
    final tempDirPath = await _getDir().then((d) => d.path);
    final hashedKey = sha256.convert(utf8.encode(key)).toString();
    final path = "$tempDirPath/$hashedKey.png";
    try {
      final file = await File(path).writeAsBytes(bytes);
      return file.path;
    } on FileSystemException catch (e) {
      log("저장중 오류가 발생했습니다. 메시지: ${e.message}", name: "ImageSaveUtil");
      rethrow;
    }
  }

  /* ----- TempDir ----- */
  /// 완료된 Directory 가 아니라 초기화 Future 를 캐싱한다.
  /// [saveImage] 가 동시에 호출되면(예: 마커 아이콘 여러 개를 `Future.wait` 로 생성)
  /// 초기화가 끝나기 전이라 모두 [_initTempDir] 을 각자 실행하게 되는데,
  /// [_cleanUpPreviousTempDir] 이 형제 폴더를 전부 지우므로 서로가 방금 만든
  /// 폴더를 삭제해버려 이후 쓰기가 `Cannot open file` 로 실패한다.
  static Future<Directory>? _imageTempDir;

  static Future<Directory> _getDir() =>
      _imageTempDir ??= _initTempDir().onError((error, stackTrace) {
        _imageTempDir = null; // 실패한 Future 는 캐싱하지 않는다 — 다음 호출에서 재시도.
        Error.throwWithStackTrace(error!, stackTrace);
      });

  static Future<Directory> _initTempDir() async {
    final tempDir = await getTemporaryDirectory();
    final targetFolderDir = Directory("${tempDir.path}/$_newTempFolderPath");
    await _cleanUpLegacyTempDir(targetFolderDir);
    await _cleanUpPreviousTempDir(targetFolderDir);
    final imageTempDirParent = await targetFolderDir.create();
    final imageTempDir = await imageTempDirParent.createTemp(_newPathPrefix);
    return imageTempDir;
  }

  static Future<void> _cleanUpPreviousTempDir(Directory imgTempDir) async {
    if (!(await imgTempDir.exists())) return; // guard.

    final previousCacheFolderStream = imgTempDir.list();
    final previousCacheFolders = await previousCacheFolderStream.toList();

    for (final folder in previousCacheFolders) {
      folder.delete(recursive: true); // not wait.
    }
  }

  static Future<void> _cleanUpLegacyTempDir(Directory newCacheFolderDir) async {
    // new version folder detected. return fast.
    if (await newCacheFolderDir.exists()) return;

    final tempDir = await getTemporaryDirectory();
    final subDirSteam = tempDir.list();

    await for (final dir in subDirSteam) {
      if (dir case Directory(:final path)) {
        final name = path.split("/").last;
        if (name.startsWith(_oldV1PathPrefix)) {
          dir.delete(recursive: true); // not wait.
        }
      }
    }
  }

  /// using <= 1.4.2
  static const _oldV1PathPrefix = "img_";

  /// currently using (1.4.3~)
  static const _newTempFolderPath = "fnm1_img";
  static const _newPathPrefix = "fnm1_img_";
}
