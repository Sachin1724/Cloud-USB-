import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config.dart';

class FilePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> fileItem;
  final String currentPath;
  final String? selectedDrive;

  const FilePreviewScreen({
    super.key,
    required this.fileItem,
    required this.currentPath,
    this.selectedDrive,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  bool _isLoading = true;
  String? _error;
  Uint8List? _fileBytes;
  String? _textContent;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  late final String _name;
  late final String _ext;
  late final String _brokerUrl;

  @override
  void initState() {
    super.initState();
    _name = widget.fileItem['name'] as String? ?? 'Unknown';
    _ext = _name.split('.').last.toLowerCase();
    _brokerUrl = AppConfig.brokerUrl;
    _loadFile();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  bool get _isImage => ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(_ext);
  bool get _isVideo => ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(_ext);
  bool get _isAudio => ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'].contains(_ext);
  bool get _isText => ['txt', 'md', 'log', 'dart', 'js', 'ts', 'py', 'json', 'html', 'css', 'xml', 'yaml', 'csv'].contains(_ext);

  Future<void> _loadFile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final relPath = widget.currentPath == '\\' ? _name : '${widget.currentPath}\\$_name';
      final driveParam = widget.selectedDrive != null ? '&drive=${Uri.encodeComponent(widget.selectedDrive!)}' : '';

      if (_isVideo) {
        // For video, use streaming URL directly
        final videoUrl = '$_brokerUrl/api/fs/video?path=${Uri.encodeComponent(relPath)}$driveParam&token=${token ?? ''}';
        _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await _videoController!.initialize();
        setState(() { _videoInitialized = true; _isLoading = false; });
        _videoController!.play();
        return;
      }

      final url = Uri.parse('$_brokerUrl/api/fs/download?path=${Uri.encodeComponent(relPath)}$driveParam');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        if (_isText) {
          setState(() { _textContent = utf8.decode(response.bodyBytes, allowMalformed: true); _isLoading = false; });
        } else if (_isAudio) {
          // Save audio to temp and play
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/$_name');
          await file.writeAsBytes(response.bodyBytes);
          _setupAudioPlayer(file.path);
          setState(() { _fileBytes = response.bodyBytes; _isLoading = false; });
        } else {
          setState(() { _fileBytes = response.bodyBytes; _isLoading = false; });
        }
      } else {
        setState(() { _error = 'Failed to load file (${response.statusCode})'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Error: $e'; _isLoading = false; });
    }
  }

  void _setupAudioPlayer(String filePath) {
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _audioDuration = d));
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _audioPosition = p));
    _audioPlayer.onPlayerStateChanged.listen((s) => setState(() => _isPlaying = s == PlayerState.playing));
    _audioPlayer.play(DeviceFileSource(filePath));
  }

  Future<void> _downloadAndOpen() async {
    try {
      if (_fileBytes != null) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_name');
        await file.writeAsBytes(_fileBytes!);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── VIEWERS ───────────────────────────────────────────────────────────────

  Widget _buildImageViewer() {
    return PhotoView(
      imageProvider: MemoryImage(_fileBytes!),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      backgroundDecoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
      loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655))),
    );
  }

  Widget _buildVideoViewer() {
    if (!_videoInitialized) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)));
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
        ),
        VideoProgressIndicator(_videoController!, allowScrubbing: true,
          colors: const VideoProgressColors(playedColor: Color(0xFFFF4655), bufferedColor: Colors.grey)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(_videoController!.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                color: const Color(0xFFFF4655), size: 48),
              onPressed: () {
                setState(() {
                  _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAudioViewer() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF4655).withValues(alpha: 0.1),
              border: Border.all(color: const Color(0xFFFF4655).withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.headphones, color: Color(0xFFFF4655), size: 80),
          ),
          const SizedBox(height: 32),
          Text(_name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              Slider(
                value: _audioPosition.inSeconds.toDouble().clamp(0, _audioDuration.inSeconds.toDouble()),
                max: _audioDuration.inSeconds.toDouble().clamp(1, double.infinity),
                activeColor: const Color(0xFFFF4655),
                onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt())),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_audioPosition), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_formatDuration(_audioDuration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 16),
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle, color: const Color(0xFFFF4655), size: 64),
            onPressed: () {
              if (_isPlaying) { _audioPlayer.pause(); } else { _audioPlayer.resume(); }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextViewer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _textContent ?? '',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _buildGenericViewer(String name, int size) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_drive_file, size: 120, color: Colors.grey.withValues(alpha: 0.6)),
          const SizedBox(height: 20),
          Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('${(size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: _downloadAndOpen,
            icon: const Icon(Icons.download, color: Colors.white),
            label: const Text('Download & Open', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int size = widget.fileItem['size'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_fileBytes != null)
            IconButton(icon: const Icon(Icons.download), tooltip: 'Download', onPressed: _downloadAndOpen),
        ],
      ),
      body: _isLoading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFFFF4655)),
                SizedBox(height: 16),
                Text('Loading file...', style: TextStyle(color: Colors.grey)),
              ],
            ))
          : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFFF4655), size: 64),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () { setState(() { _isLoading = true; _error = null; }); _loadFile(); },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
                      child: const Text('Retry', style: TextStyle(color: Colors.white))),
                  ],
                ))
              : _isImage && _fileBytes != null
                  ? _buildImageViewer()
                  : _isVideo
                      ? _buildVideoViewer()
                      : _isAudio
                          ? _buildAudioViewer()
                          : _isText
                              ? _buildTextViewer()
                              : _buildGenericViewer(_name, size),
    );
  }
}
