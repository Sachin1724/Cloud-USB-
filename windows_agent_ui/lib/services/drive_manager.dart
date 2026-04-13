import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

class DriveManager {
  static final Map<String, IOSink> _activeUploads = {};

  static Future<String> _getRootPath() async {
    final prefs = await SharedPreferences.getInstance();
    // Use the exact string key 'selected_drive' that the UI saves, not a list.
    final drive = prefs.getString('selected_drive');
    if (drive != null && drive.isNotEmpty) {
      // Ensure trailing slash for Windows drives (e.g. "G:\")
      return drive.endsWith('\\') ? drive : '$drive\\';
    }
    return 'D:\\';
  }

  static Future<String> _getSafePath(String? subPath, {String? driveOverride}) async {
    // Use the drive override if provided (from request), otherwise use registered drive
    String root;
    if (driveOverride != null && driveOverride.isNotEmpty) {
      root = driveOverride.endsWith('\\') ? driveOverride : '$driveOverride\\';
    } else {
      root = await _getRootPath();
    }
    debugPrint('[DriveNet] _getSafePath: root=$root, subPath=$subPath');
    
    // Handle empty or null path - use root
    if (subPath == null || subPath.isEmpty || subPath == r'\') {
      return root;
    }
    
    // Decode URL-encoded backslashes (e.g., %5C -> \)
    String decodedPath = subPath.replaceAll('%5C', r'\').replaceAll('%5c', r'\');
    debugPrint('[DriveNet] _getSafePath: decodedPath=$decodedPath');
    
    // Check if it's a full drive path like "E:\" - validate against registered drive
    if (decodedPath.length >= 2 && decodedPath[1] == ':') {
      String requestedDriveRoot = '${decodedPath.substring(0, 2).toUpperCase()}\\';
      String registeredDriveRoot = '${root.substring(0, 2).toUpperCase()}\\';
      
      // Only allow the registered drive
      if (requestedDriveRoot != registeredDriveRoot) {
        debugPrint('[DriveNet] _getSafePath: REJECTED - requested drive $requestedDriveRoot != registered $registeredDriveRoot');
        throw Exception('Access Denied: Can only access registered drive ($registeredDriveRoot)');
      }
      
      String normalizedPath = p.normalize(decodedPath);
      debugPrint('[DriveNet] _getSafePath: drive path validated: $normalizedPath');
      return normalizedPath;
    }
    
    // Build target path for relative paths
    String targetPath;
    if (decodedPath.startsWith(r'\')) {
      // Absolute path from root (e.g., "\folder")
      targetPath = root + decodedPath.substring(1);
    } else {
      // Relative path
      targetPath = root + decodedPath;
    }
    
    // Normalize the path (handle .., ., etc)
    targetPath = p.normalize(targetPath);
    debugPrint('[DriveNet] _getSafePath: targetPath=$targetPath');
    
    if (!targetPath.toLowerCase().startsWith(root.toLowerCase())) {
      throw Exception('Access Denied: Path Traversal Attempted');
    }
    return targetPath;
  }

  static Future<dynamic> handleFileRequest(
      String action, Map<String, dynamic> payload, void Function(Map<String, dynamic>) wsSend, String requestId) async {
    // Get the drive from payload (can override the default registered drive)
    final String? driveOverride = payload['drive'] as String?;
    debugPrint('[DriveNet] handleFileRequest: action=$action, driveOverride=$driveOverride');
    
    switch (action) {
      case 'fs:list':
        return await _listFiles(payload['path'] as String?, driveOverride: driveOverride);
      case 'fs:mkdir':
        return await _createFolder(payload['path'] as String?, payload['name'] as String?, driveOverride: driveOverride);
      case 'fs:delete':
        return await _deleteItem(payload['path'] as String?, driveOverride: driveOverride);
      case 'fs:rename':
        return await _renameItem(payload['oldPath'] as String?, payload['newPath'] as String?, driveOverride: driveOverride);
      case 'fs:upload_chunk':
        return await _handleUploadChunk(payload, driveOverride: driveOverride);
      case 'fs:download':
        await _downloadFile(payload['path'] as String?, wsSend, requestId, driveOverride: driveOverride);
        return null;
      case 'fs:stream':
        await _streamFile(payload['path'] as String?, payload['headers'] as Map<String, dynamic>?, payload['quality'] as String?, wsSend, requestId, driveOverride: driveOverride);
        return null;
      case 'fs:thumbnail':
        return await _getThumbnail(payload['path'] as String?, wsSend, requestId, driveOverride: driveOverride);
      case 'sys:stats':
        return await _collectStats(driveOverride: driveOverride);
      // ─── NEW: SEARCH, TRASH, RESTORE ────────────────────────────────────────
      case 'fs:search':
        return await _searchFiles(payload['q'] as String? ?? payload['query'] as String? ?? '', payload['path'] as String?, driveOverride: driveOverride);
      case 'fs:trash':
        return await _moveToTrash(payload['path'] as String?, driveOverride: driveOverride);
      case 'fs:trash_list':
        return await _listTrash(driveOverride: driveOverride);
      case 'fs:restore':
        return await _restoreFromTrash(payload['path'] as String?, driveOverride: driveOverride);
      case 'fs:trash_purge':
        return await _purgeFromTrash(payload['path'] as String?, driveOverride: driveOverride);
      default:
        throw Exception('Unknown filesystem action: $action');
    }
  }

  static Future<Map<String, dynamic>> _listFiles(String? dirPath, {String? driveOverride}) async {
    debugPrint('[DriveNet] _listFiles called with path: $dirPath, driveOverride: $driveOverride');
    final target = await _getSafePath(dirPath, driveOverride: driveOverride);
    debugPrint('[DriveNet] _listFiles target path: $target');
    final dir = Directory(target);
    if (!await dir.exists()) {
      throw Exception('Path is not a directory');
    }

    final items = <Map<String, dynamic>>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        items.add({
          'name': p.basename(entity.path),
          'is_dir': isDir,
          'size': isDir ? 0 : stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
      } catch (_) {
        // Ignore permission denied
      }
    }
    return {'path': dirPath ?? '', 'items': items};
  }

  static Future<Map<String, dynamic>> _createFolder(String? parentPath, String? folderName, {String? driveOverride}) async {
    if (folderName == null || folderName.isEmpty) throw Exception('Folder name required');
    final target = await _getSafePath(p.join(parentPath ?? '', folderName), driveOverride: driveOverride);
    await Directory(target).create(recursive: true);
    return {'success': true, 'path': target};
  }

  static Future<Map<String, dynamic>> _deleteItem(String? itemPath, {String? driveOverride}) async {
    if (itemPath == null || itemPath.isEmpty) throw Exception('Path required');
    final target = await _getSafePath(itemPath, driveOverride: driveOverride);
    final stat = await FileStat.stat(target);
    if (stat.type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (stat.type == FileSystemEntityType.file) {
      await File(target).delete();
    }
    return {'success': true};
  }

  static Future<Map<String, dynamic>> _renameItem(String? oldPath, String? newPath, {String? driveOverride}) async {
    if (oldPath == null || oldPath.isEmpty) throw Exception('oldPath required');
    if (newPath == null || newPath.isEmpty) throw Exception('newPath required');

    final source = await _getSafePath(oldPath, driveOverride: driveOverride);
    final target = await _getSafePath(newPath, driveOverride: driveOverride);
    final stat = await FileStat.stat(source);
    if (stat.type == FileSystemEntityType.notFound) throw Exception('Source not found');

    if (stat.type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else if (stat.type == FileSystemEntityType.file) {
      await File(source).rename(target);
    } else {
      throw Exception('Unsupported entity type');
    }

    return {'success': true, 'oldPath': oldPath, 'newPath': newPath};
  }

  static Future<Map<String, dynamic>> _handleUploadChunk(Map<String, dynamic> payload, {String? driveOverride}) async {
    final uploadId = payload['uploadId'] as String;
    final folderPath = payload['path'] as String?;
    final name = payload['name'] as String;
    final chunkBase64 = payload['chunk'] as String;
    final isFirst = payload['isFirst'] as bool;
    final isLast = payload['isLast'] as bool;

    final targetDir = await _getSafePath(folderPath, driveOverride: driveOverride);
    final targetFile = p.join(targetDir, name);
    await _getSafePath(targetFile, driveOverride: driveOverride);

    if (isFirst) {
      if (_activeUploads.containsKey(uploadId)) {
        await _activeUploads[uploadId]!.close();
        _activeUploads.remove(uploadId);
      }
      final file = File(targetFile);
      await file.parent.create(recursive: true);
      _activeUploads[uploadId] = file.openWrite(mode: FileMode.append);
    }

    final sink = _activeUploads[uploadId];
    if (sink == null) throw Exception('Upload stream not found');

    String base64Str = chunkBase64;
    if (base64Str.contains(',')) {
      base64Str = base64Str.split(',').last;
    }

    if (base64Str.isNotEmpty) {
      sink.add(base64Decode(base64Str));
    }

    if (isLast) {
      await sink.close();
      _activeUploads.remove(uploadId);
      return {'success': true, 'finished': true};
    } else {
      return {'success': true, 'finished': false};
    }
  }

  static Future<void> _downloadFile(String? filePath, void Function(Map<String, dynamic>) wsSend, String requestId, {String? driveOverride}) async {
    if (filePath == null) throw Exception('File path required');
    final target = await _getSafePath(filePath, driveOverride: driveOverride);
    final file = File(target);
    if (!await file.exists()) throw Exception('Cannot download a directory or missing file');
    
    final size = await file.length();
    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'start',
        'filename': p.basename(target),
        'size': size,
      }
    });

    final stream = file.openRead();
    List<int> buffer = [];
    const chunkSize = 1024 * 1024; // 1MB chunks
    
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      if (buffer.length >= chunkSize) {
        wsSend({
          'requestId': requestId,
          'payload': {
            'type': 'chunk',
            'data': base64Encode(buffer),
          }
        });
        buffer.clear();
      }
    }
    
    if (buffer.isNotEmpty) {
      wsSend({
        'requestId': requestId,
        'payload': {
          'type': 'chunk',
          'data': base64Encode(buffer),
        }
      });
    }

    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'end',
      }
    });
  }

  static Future<void> _streamFile(String? filePath, Map<String, dynamic>? headers, String? quality, void Function(Map<String, dynamic>) wsSend, String requestId, {String? driveOverride}) async {
    if (filePath == null) throw Exception('File path required');
    final target = await _getSafePath(filePath, driveOverride: driveOverride);
    final file = File(target);
    if (!await file.exists()) {
      wsSend({
        'requestId': requestId,
        'error': 'File not found'
      });
      return;
    }

    final bool useTranscode = (quality == 'low' || quality == 'auto');
    if (useTranscode && (target.toLowerCase().endsWith('.mp4') || target.toLowerCase().endsWith('.mov') || target.toLowerCase().endsWith('.avi') || target.toLowerCase().endsWith('.webm') || target.toLowerCase().endsWith('.mkv'))) {
      await _streamTranscode(target, wsSend, requestId);
      return;
    }
    
    final fileSize = await file.length();
    final rangeHeader = headers?['range']?.toString();
    
    int start = 0;
    int end = fileSize - 1;
    bool isPartial = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeStr = rangeHeader.substring(6).split('-');
      if (rangeStr[0].isNotEmpty) start = int.parse(rangeStr[0]);
      if (rangeStr.length > 1 && rangeStr[1].isNotEmpty) {
        end = int.parse(rangeStr[1]);
      }
      isPartial = true;
    }

    if (start >= fileSize || end >= fileSize || start > end) {
      wsSend({
        'requestId': requestId,
        'payload': {
          'type': 'start',
          'statusCode': 416,
          'headers': {
            'Content-Range': 'bytes */$fileSize'
          }
        }
      });
      wsSend({'requestId': requestId, 'payload': {'type': 'end'}});
      return;
    }

    final chunkLength = end - start + 1;
    // Cap chunk length to prevent sending too much data at once over WS. Browsers will request more.
    final maxChunkLength = 1024 * 1024 * 5; // 5MB limit per range request
    int actualEnd = end;
    
    if (chunkLength > maxChunkLength) {
      actualEnd = start + maxChunkLength - 1;
    }
    final contentLength = actualEnd - start + 1;

    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'start',
        'statusCode': isPartial ? 206 : 200,
        'headers': {
          'Content-Range': 'bytes $start-$actualEnd/$fileSize',
          'Accept-Ranges': 'bytes',
          'Content-Length': contentLength.toString(),
          'Content-Type': 'video/mp4', // Default to video/mp4, though the browser usually knows by looking at the first chunk
        }
      }
    });

    final stream = file.openRead(start, actualEnd + 1);
    List<int> buffer = [];
    const packetSize = 1024 * 512; // 512KB packets
    
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      if (buffer.length >= packetSize) {
        wsSend({
          'requestId': requestId,
          'payload': {
            'type': 'chunk',
            'data': base64Encode(buffer),
          }
        });
        buffer.clear();
      }
    }
    
    if (buffer.isNotEmpty) {
      wsSend({
        'requestId': requestId,
        'payload': {
          'type': 'chunk',
          'data': base64Encode(buffer),
        }
      });
    }

    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'end',
      }
    });
  }

  static Future<void> _streamTranscode(String target, void Function(Map<String, dynamic>) wsSend, String requestId) async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final ffmpegPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'ffmpeg.exe');
    final actualFfmpeg = File(ffmpegPath).existsSync() ? ffmpegPath : 'ffmpeg';

    wsSend({
      'requestId': requestId,
      'payload': {
        'type': 'start',
        'statusCode': 200,
        'headers': {
          'Content-Type': 'video/mp4',
        }
      }
    });

    try {
      final process = await Process.start(actualFfmpeg, [
        '-i', target,
        '-vf', 'scale=-2:480',
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-crf', '28',
        '-c:a', 'aac',
        '-f', 'mp4',
        '-movflags', 'frag_keyframe+empty_moov',
        'pipe:1'
      ]);

      List<int> buffer = [];
      const packetSize = 1024 * 512; // 512KB

      process.stdout.listen((event) {
        buffer.addAll(event);
        if (buffer.length >= packetSize) {
          wsSend({
            'requestId': requestId,
            'payload': {
              'type': 'chunk',
              'data': base64Encode(buffer),
            }
          });
          buffer.clear();
        }
      }, onDone: () {
        if (buffer.isNotEmpty) {
          wsSend({
            'requestId': requestId,
            'payload': {
              'type': 'chunk',
              'data': base64Encode(buffer),
            }
          });
        }
        wsSend({
          'requestId': requestId,
          'payload': {
            'type': 'end',
          }
        });
      }, onError: (e) {
        wsSend({'requestId': requestId, 'payload': {'type': 'end'}});
      });

      process.stderr.listen((_) {}); // Ignore logs
    } catch (e) {
      wsSend({'requestId': requestId, 'payload': {'type': 'end'}});
    }
  }

  static Future<dynamic> _getThumbnail(String? filePath, void Function(Map<String, dynamic>) wsSend, String requestId, {String? driveOverride}) async {
    if (filePath == null) throw Exception('File path required');
    final target = await _getSafePath(filePath, driveOverride: driveOverride);
    final file = File(target);
    if (!await file.exists()) throw Exception('Cannot thumbnail a directory');

    try {
      final bytes = await file.readAsBytes();
      final base64String = await Isolate.run(() {
        final image = img.decodeImage(bytes);
        if (image == null) throw Exception('Could not decode image');
        final resized = img.copyResize(image, width: 200);
        final jpg = img.encodeJpg(resized, quality: 70);
        return base64Encode(jpg);
      });

      return {
        'isFile': true,
        'filename': 'thumb_${p.basename(target)}.jpg',
        'payload': base64String,
      };
    } catch (e) {
      debugPrint('Thumbnail error: $e.');
      await _downloadFile(filePath, wsSend, requestId);
      return null;
    }
  }

  static Future<Map<String, dynamic>> _collectStats({String? driveOverride}) async {
    final root = driveOverride ?? await _getRootPath();
    int total = 0;
    int free = 0;
    try {
      final queryDrive = root.endsWith('\\') ? root.substring(0, root.length - 1) : root;
      final result = await Process.run('powershell', [
        '-Command',
        'Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq "$queryDrive" | Select-Object Size, FreeSpace | ConvertTo-Json'
      ]);
      if (result.exitCode == 0) {
        final dat = jsonDecode(result.stdout);
        total = int.tryParse(dat['Size']?.toString() ?? '0') ?? 0;
        free = int.tryParse(dat['FreeSpace']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}

    return {
      'cpu': 5.0,
      'ram': 25.0,
      'up': 0.0,
      'down': 0.0,
      'storageTotal': total,
      'storageAvailable': free,
      'storageUsed': total - free,
    };
  }

  // ─── SEARCH ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _searchFiles(String query, String? startPath, {String? driveOverride}) async {
    if (query.trim().isEmpty) return {'items': []};
    final root = await _getSafePath(startPath, driveOverride: driveOverride);
    final results = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase();

    Future<void> walkDir(String dirPath, int depth) async {
      if (depth > 8 || results.length >= 200) return;
      try {
        final dir = Directory(dirPath);
        await for (final entity in dir.list(followLinks: false)) {
          try {
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            if (name.toLowerCase().contains(lowerQuery)) {
              final stat = await entity.stat();
              results.add({
                'name': name,
                'path': entity.path,
                'is_dir': entity is Directory,
                'size': entity is File ? stat.size : 0,
                'modified': stat.modified.millisecondsSinceEpoch,
              });
            }
            if (entity is Directory && depth < 8) {
              await walkDir(entity.path, depth + 1);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    await walkDir(root, 0);
    return {'items': results, 'query': query};
  }

  // ─── TRASH ────────────────────────────────────────────────────────────────────

  static String _trashDir(String root) {
    final base = root.endsWith('\\') ? root : '$root\\';
    return '$base.drivenet_trash';
  }

  static Future<Map<String, dynamic>> _moveToTrash(String? itemPath, {String? driveOverride}) async {
    if (itemPath == null || itemPath.isEmpty) throw Exception('Path required');
    final source = await _getSafePath(itemPath, driveOverride: driveOverride);
    final root = driveOverride ?? await _getRootPath();
    final trashDir = _trashDir(root);
    await Directory(trashDir).create(recursive: true);

    final name = p.basename(source);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(trashDir, '${name}__$stamp');

    final stat = await FileStat.stat(source);
    if (stat.type == FileSystemEntityType.directory) {
      await Directory(source).rename(dest);
    } else {
      await File(source).rename(dest);
    }

    final meta = {'original': source, 'name': name, 'stamp': stamp, 'is_dir': stat.type == FileSystemEntityType.directory};
    await File('$dest.meta').writeAsString(jsonEncode(meta));
    return {'success': true, 'trashPath': dest};
  }

  static Future<Map<String, dynamic>> _listTrash({String? driveOverride}) async {
    final root = driveOverride ?? await _getRootPath();
    final trashDir = _trashDir(root);
    final items = <Map<String, dynamic>>[];
    final dir = Directory(trashDir);
    if (!await dir.exists()) return {'items': []};

    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.endsWith('.meta')) continue;
      try {
        final metaFile = File('${entity.path}.meta');
        Map<String, dynamic> meta = {};
        if (await metaFile.exists()) {
          meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        }
        final stat = await entity.stat();
        items.add({
          'name': meta['name'] ?? name,
          'trashPath': entity.path,
          'original': meta['original'] ?? '',
          'is_dir': entity is Directory,
          'size': entity is File ? stat.size : 0,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
    return {'items': items};
  }

  static Future<Map<String, dynamic>> _restoreFromTrash(String? trashPath, {String? driveOverride}) async {
    if (trashPath == null || trashPath.isEmpty) throw Exception('trashPath required');
    final metaFile = File('$trashPath.meta');
    if (!await metaFile.exists()) throw Exception('No metadata found for trash item');
    final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final original = meta['original'] as String;
    final isDir = meta['is_dir'] as bool? ?? false;

    await Directory(p.dirname(original)).create(recursive: true);
    if (isDir) {
      await Directory(trashPath).rename(original);
    } else {
      await File(trashPath).rename(original);
    }
    await metaFile.delete();
    return {'success': true, 'restored': original};
  }

  static Future<Map<String, dynamic>> _purgeFromTrash(String? trashPath, {String? driveOverride}) async {
    if (trashPath == null || trashPath.isEmpty) throw Exception('trashPath required');
    final stat = await FileStat.stat(trashPath);
    if (stat.type == FileSystemEntityType.directory) {
      await Directory(trashPath).delete(recursive: true);
    } else if (stat.type == FileSystemEntityType.file) {
      await File(trashPath).delete();
    }
    final metaFile = File('$trashPath.meta');
    if (await metaFile.exists()) await metaFile.delete();
    return {'success': true};
  }
}
