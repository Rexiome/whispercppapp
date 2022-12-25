import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

const APPDIR = 'org.hogel.whispercppapp';
const TRANSCRIPT_NAME = 'transcript.txt';
final PATTERN_TIMINGS = RegExp(r'^\[[^\]]+\]  ', multiLine: true);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeWidget(),
    );
  }
}

class HomeWidget extends StatefulWidget {
  const HomeWidget({Key? key}) : super(key: key);

  @override
  _HomeWidgetState createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  XFile? _dropFile = null;
  bool _dragging = false;
  bool _converting = false;
  String _consoleText = '';
  String _transcriptText = '';
  String _transcriptTextWithTimings = '';

  Directory? _appTempDir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Speech recognition'),
      ),
      body: Container(
        margin: EdgeInsets.all(20),
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    DropTarget(
                      onDragDone: (detail) {
                        setState(() {
                          _dropFile = detail.files.first;
                          _dragging = false;
                        });
                      },
                      onDragEntered: (detail) {
                        setState(() {
                          _dragging = true;
                        });
                      },
                      onDragExited: (detail) {
                        setState(() {
                          _dragging = false;
                        });
                      },
                      child: Expanded(child:
                      Container(
                        height: 100,
                        color: _dragging ? Colors.blue.withOpacity(0.4) : Colors.black12,
                        child: TextButton(
                          onPressed: () async {
                            final XFile? file = await openFile();
                            if (file != null) {
                              setState(() {
                                _dropFile = file;
                              });
                            }
                          },
                          child: Text(_dropFile == null ? "Drop audio file here" : _dropFile!.path),
                        ),
                      )
                      ),
                    ),
                    Container(width: 10),
                    ElevatedButton(
                      onPressed: _runnable() ? _runRecognition : null,
                      child: _converting ? const CircularProgressIndicator(color: Colors.blue) : const Icon(Icons.play_arrow),
                    ),
                  ],
                ),
                LabeledTextArea(
                  label: 'Console output',
                  text: _consoleText,
                  height: 150,
                ),
                LabeledTextArea(
                  label: 'Transcript',
                  text: _transcriptText,
                  height: 200,
                ),
                SaveButton(_transcriptText),
                LabeledTextArea(
                  label: 'Transcript with timings',
                  text: _transcriptTextWithTimings,
                  height: 200,
                ),
                SaveButton(_transcriptTextWithTimings),
              ],
            )
          ),
        ),
      ),
    );
  }

  bool _runnable() => !_converting && _dropFile != null;

  Future<Directory?> _setup() async {
    Directory userTempDir = await getTemporaryDirectory();
    _appTempDir = await Directory(path.join(userTempDir.path, APPDIR)).create();
    return _appTempDir;
  }

  void _runRecognition() async {
    await _setup();

    setState(() {
      _converting = true;
      _consoleText = '';
    });
    try {
      File wavfile = await _convertWavfile(_dropFile!.path);
      await _transcript(wavfile);
    } catch (e) {
      _consoleWrite(e.toString());
    } finally {
      setState(() {
        _dropFile = null;
        _converting = false;
      });
    }
  }

  Future<File> _convertWavfile(String sourceFile) async {
    File wavfile = File(path.join(_appTempDir!.path, "input.wav"));
    if (wavfile.existsSync()) {
      wavfile.deleteSync();
    }
    var args = ['-i', _dropFile!.path, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wavfile.path];
    await _runCommand('ffmpeg', args);
    return wavfile;
  }

  Future<String> _transcript(File wavfile) async {
    String whisperPath = path.join(_appTempDir!.path, 'app', 'whispercpp');
    String modelPath = path.join(_appTempDir!.path, 'app', 'ggml-medium.bin');
    var args = ['-m', modelPath, '-l', 'ja', '-f', wavfile.path];

    var result = await _runCommand(whisperPath, args);

    var textWithTimings = result.stdout.trim();
    setState(() {
      _transcriptTextWithTimings = textWithTimings;
      _transcriptText = textWithTimings.replaceAll(PATTERN_TIMINGS, '');
    });
    return _transcriptTextWithTimings;
  }

  Future<ProcessResult> _runCommand(String command, List<String> args) async {
    _consoleWrite("\$ $command ${ args.join(' ') }\n");
    var process = await Process.start(command, args);
    var stdout = '';
    var stderr = '';
    process.stderr.transform(utf8.decoder).forEach((line) {
      stderr += line;
      _consoleWrite(line);
    });
    process.stdout.transform(utf8.decoder).forEach((line) {
      stdout += line;
      _consoleWrite(line);
    });

    var exitCode = await process.exitCode;
    _consoleWrite('\n');

    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }

  void _consoleWrite(String line) {
    setState(() {
      _consoleText += line;
    });
  }
}

class LabeledTextArea extends StatelessWidget {
  const LabeledTextArea({super.key, required this.label, required this.text, this.height = null});

  final String label;
  final String text;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: height,
        width: double.infinity,
        child: Column(
          children: [
            Container(height: 10),
            Container(
              padding: EdgeInsets.all(4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(label, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            Scrollbar(
              child: SingleChildScrollView(
                child: Container(
                  height: height != null ? height! - 40.0 : null,
                  width: double.infinity,
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black45)),
                  child: SelectableText(
                    text,
                  ),
                  // child: SelectableText(_consoleText),
                ),
              ),
            )
          ],
        ),
    );
  }
}

class SaveButton extends StatelessWidget {
  const SaveButton(String this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ElevatedButton(
        onPressed: text.length > 0 ? _saveTranscript : null,
        child: Text('Save'),
      ),
    );
  }

  void _saveTranscript() async {
    final String? path = await getSavePath(suggestedName: TRANSCRIPT_NAME);
    if (path == null) {
      return;
    }

    final Uint8List fileData = Uint8List.fromList(utf8.encode(text));
    final XFile textFile = XFile.fromData(fileData, mimeType: 'text/plain', name: TRANSCRIPT_NAME);
    await textFile.saveTo(path);
  }
}
