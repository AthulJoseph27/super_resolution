import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

void main() {
  runApp(const SuperResApp());
}

class SuperResApp extends StatelessWidget {
  const SuperResApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-ESRGAN Turbo GPU',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.cyan,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  File? _resultImage;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = "Initializing...";
  String _modeUsed = ""; // To track if GPU or CPU was used

  ResolutionTarget _selectedTarget = ResolutionTarget.fhd;
  String? _modelPath;

  @override
  void initState() {
    super.initState();
    _prepareModel();
  }

  Future<void> _prepareModel() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelFile = File('${directory.path}/real_esrgan.tflite');

      if (!await modelFile.exists()) {
        final byteData = await rootBundle.load('assets/real_esrgan.tflite');
        final buffer = byteData.buffer;
        await modelFile.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      }

      setState(() {
        _modelPath = modelFile.path;
        _statusMessage = "Ready. GPU Acceleration Enabled.";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Model Load Failed: Check assets.";
      });
      print("Model Error: $e");
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _resultImage = null;
          _progress = 0.0;
          _statusMessage = "Image selected. Tap Enhance.";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "PICKER ERROR: $e";
      });
    }
  }

  Future<void> _saveImage() async {
    if (_resultImage == null) return;

    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) throw Exception("Downloads directory not found");

        final fileName = "realesrgan_${DateTime.now().millisecondsSinceEpoch}.png";
        final savePath = "${downloadsDir.path}/$fileName";
        await _resultImage!.copy(savePath);

        setState(() => _statusMessage = "Saved to Downloads!");

        if (Platform.isMacOS) {
          await Process.run('open', ['-R', savePath]);
        }
      } else {
        await Gal.putImage(_resultImage!.path);
        setState(() => _statusMessage = "Saved to Photos Gallery!");
      }
    } catch (e) {
      setState(() => _statusMessage = "Save Error: $e");
    }
  }

  Future<void> _runSuperResolution() async {
    if (_selectedImage == null || _modelPath == null) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = "Initializing Accelerator...";
    });

    try {
      final receivePort = ReceivePort();

      final args = {
        'imagePath': _selectedImage!.path,
        'modelPath': _modelPath,
        'targetIndex': _selectedTarget.index,
        'sendPort': receivePort.sendPort,
      };

      // Spawn ONE isolate. GPU cannot be shared across isolates easily.
      await Isolate.spawn(_inferenceIsolateEntry, args);

      await for (final message in receivePort) {
        if (message is Map && message.containsKey('progress')) {
          setState(() {
            _progress = message['progress'];
            _statusMessage = "Enhancing: ${(message['progress'] * 100).toInt()}%";
          });
        } else if (message is Map && message.containsKey('mode')) {
          _modeUsed = message['mode'];
        } else if (message is Uint8List) {
          final tempDir = await getTemporaryDirectory();
          final resultFile = File('${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.png');
          await resultFile.writeAsBytes(message);

          if (mounted) {
            setState(() {
              _resultImage = resultFile;
              _statusMessage = "Complete! ($_modeUsed)";
              _isProcessing = false;
            });
          }
          receivePort.close();
          break;
        } else if (message is String) {
          if (message.startsWith("ERROR:")) {
            setState(() {
              _statusMessage = message;
              _isProcessing = false;
            });
            receivePort.close();
          } else {
            print("ISOLATE LOG: $message");
          }
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = "System Error: $e";
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canEnhance = !_isProcessing && _selectedImage != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Real-ESRGAN Turbo")),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildImagePanel("Original", _selectedImage)),
                const VerticalDivider(width: 1, color: Colors.white24),
                Expanded(child: _buildImagePanel("Enhanced", _resultImage)),
              ],
            ),
          ),
          if (_isProcessing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress, color: Colors.cyanAccent),
                  const SizedBox(height: 5),
                  Text("${(_progress * 100).toInt()}%", style: const TextStyle(color: Colors.cyanAccent)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black26,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.contains("Error") ? Colors.redAccent : Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<ResolutionTarget>(
                      value: _selectedTarget,
                      decoration: const InputDecoration(labelText: "Target Resolution", border: OutlineInputBorder()),
                      dropdownColor: Colors.grey[900],
                      items: ResolutionTarget.values.map((target) {
                        return DropdownMenuItem(value: target, child: Text(target.label));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedTarget = val!),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _pickImage,
                              icon: const Icon(Icons.image),
                              label: const Text("Pick"),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: _resultImage != null && !_isProcessing
                                ? ElevatedButton.icon(
                              onPressed: _saveImage,
                              icon: const Icon(Icons.download),
                              label: const Text("Save"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                            )
                                : ElevatedButton.icon(
                              onPressed: canEnhance ? _runSuperResolution : null,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text("Enhance"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildImagePanel(String title, File? file) {
    return Column(
      children: [
        Padding(padding: const EdgeInsets.all(8.0), child: Text(title)),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(border: Border.all(color: Colors.white10)),
            child: file == null
                ? const Center(child: Icon(Icons.image_not_supported, color: Colors.white24))
                : Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}

enum ResolutionTarget {
  fhd("1080p", 1920),
  qhd("1440p", 2560),
  uhd("4K", 3840),
  uhd8k("8K", 7680);

  final String label;
  final int width;
  const ResolutionTarget(this.label, this.width);
}

// ---------------------------------------------------------------------------
// SINGLE ISOLATE INFERENCE ENGINE (GPU + CPU FALLBACK)
// ---------------------------------------------------------------------------

Future<void> _inferenceIsolateEntry(Map<String, dynamic> args) async {
  final SendPort mainPort = args['sendPort'];

  try {
    final String imagePath = args['imagePath'];
    final String modelPath = args['modelPath'];
    final int targetIndex = args['targetIndex'];
    final ResolutionTarget target = ResolutionTarget.values[targetIndex];

    // 1. Image Preprocessing
    final imageFile = File(imagePath);
    var rawImage = img.decodeImage(imageFile.readAsBytesSync());
    if (rawImage == null) throw Exception("Could not decode image");

    int desiredInputWidth = (target.width / 4).round();
    var resizedImage = img.copyResize(
        rawImage,
        width: desiredInputWidth,
        interpolation: img.Interpolation.cubic
    );

    // 2. Initialize Interpreter (GPU Priority with CPU Fallback)
    Interpreter? interpreter;
    Delegate? delegate;
    // ignore: unused_local_variable
    bool usingGpu = false;

    // Tiling Settings
    const int modelInputSize = 128;
    const int scale = 4;
    const int padding = 16; // Overlap
    const int validSize = modelInputSize - (padding * 2);
    const int modelOutputSize = modelInputSize * scale;

    // Buffers
    var inputBuffer = Float32List(1 * modelInputSize * modelInputSize * 3).reshape([1, modelInputSize, modelInputSize, 3]);
    var outputBuffer = Float32List(1 * modelOutputSize * modelOutputSize * 3).reshape([1, modelOutputSize, modelOutputSize, 3]);

    try {
      // A. Attempt GPU Load
      final options = InterpreterOptions();

      if (Platform.isAndroid) {
        delegate = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: false,
          ),
        );
        options.addDelegate(delegate);
      } else if (Platform.isIOS || Platform.isMacOS) {
        // Shared Metal Delegate for iOS and macOS
        delegate = GpuDelegate(
            options: GpuDelegateOptions(
              allowPrecisionLoss: true,
            )
        );
        options.addDelegate(delegate);
      }

      interpreter = Interpreter.fromFile(File(modelPath), options: options);
      interpreter.allocateTensors();
      usingGpu = true;
      print("✅ GPU Delegate Initialized Successfully");
      mainPort.send({'mode': 'Using GPU Acceleration'});

    } catch (e) {
      // B. Fallback to CPU (XNNPACK)
      print("⚠️ GPU Delegate failed ($e), falling back to CPU.");

      try {
        delegate?.delete();
      } catch (_) {}
      delegate = null;

      final cpuOptions = InterpreterOptions();
      cpuOptions.threads = 4;

      interpreter = Interpreter.fromFile(File(modelPath), options: cpuOptions);
      interpreter.allocateTensors();
      usingGpu = false;
      print("💻 CPU Interpreter Initialized (4 Threads)");

      // Send the specific error reason to the UI so you can see it on screen
      String errorShort = e.toString().length > 20 ? e.toString().substring(0, 20) : e.toString();
      mainPort.send({'mode': 'CPU Fallback ($errorShort)'});
    }

    // 3. Output Canvas
    final int resultW = resizedImage.width * scale;
    final int resultH = resizedImage.height * scale;
    var finalImage = img.Image(width: resultW, height: resultH);

    // 4. Inference Loop
    int totalTiles = ((resizedImage.height / validSize).ceil()) * ((resizedImage.width / validSize).ceil());
    int processedTiles = 0;

    for (var y = 0; y < resizedImage.height; y += validSize) {
      for (var x = 0; x < resizedImage.width; x += validSize) {

        int readX = x - padding;
        int readY = y - padding;

        // Extract Tile
        for (int ty = 0; ty < modelInputSize; ty++) {
          for (int tx = 0; tx < modelInputSize; tx++) {
            int srcX = (readX + tx).clamp(0, resizedImage.width - 1);
            int srcY = (readY + ty).clamp(0, resizedImage.height - 1);

            img.Pixel pixel = resizedImage.getPixel(srcX, srcY);

            // Fill Buffer (Normalize 0-1)
            var batch = inputBuffer[0] as List;
            var row = batch[ty] as List;
            var pData = row[tx] as List;

            pData[0] = pixel.r / 255.0;
            pData[1] = pixel.g / 255.0;
            pData[2] = pixel.b / 255.0;
          }
        }

        // Run Inference
        interpreter.run(inputBuffer, outputBuffer);

        // Stitch Result
        int cropStart = padding * scale;
        int cropSize = validSize * scale;
        int pasteX = x * scale;
        int pasteY = y * scale;

        var batchOut = outputBuffer[0] as List;

        for(int cy = 0; cy < cropSize; cy++) {
          int srcY = cropStart + cy;
          if (srcY >= modelOutputSize) continue;

          int dstY = pasteY + cy;
          if (dstY >= resultH) continue;

          var row = batchOut[srcY] as List;

          for(int cx = 0; cx < cropSize; cx++) {
            int srcX = cropStart + cx;
            if (srcX >= modelOutputSize) continue;

            int dstX = pasteX + cx;
            if (dstX >= resultW) continue;

            var pixelData = row[srcX] as List;

            // Denormalize
            int r = (pixelData[0] * 255.0).clamp(0, 255).toInt();
            int g = (pixelData[1] * 255.0).clamp(0, 255).toInt();
            int b = (pixelData[2] * 255.0).clamp(0, 255).toInt();

            finalImage.setPixelRgb(dstX, dstY, r, g, b);
          }
        }

        processedTiles++;
        if (processedTiles % 5 == 0) {
          mainPort.send({'progress': processedTiles / totalTiles});
        }
      }
    }

    // Cleanup
    interpreter.close();
    try {
      delegate?.delete();
    } catch (_) {}

    // Encode and Send back
    mainPort.send(Uint8List.fromList(img.encodePng(finalImage)));

  } catch (e) {
    mainPort.send("ERROR: $e");
  } finally {
    Isolate.exit();
  }
}