import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// TODO: test and link shared pref page

List<String> splitStringByLength(String str, int length) =>
    [str.substring(0, length), str.substring(length)];

Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();

  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();

  // Get a specific camera from the list of available cameras.
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(
        // Pass the appropriate camera to the TakePictureScreen widget.
        camera: firstCamera,
      ),
    ),
  );
}

// A screen that allows users to take a picture using a given camera.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    Key? key,
    required this.camera,
  }) : super(key: key);

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final textDetector = GoogleMlKit.vision.textDetector();
  var timeStringDetected = 'No valid time detected';

  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      widget.camera,
      // Define the resolution to use.
      ResolutionPreset.medium,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  Future<File> getImageFileFromAssets(String path) async {
    final byteData = await rootBundle.load('assets/$path');

    final file = File('${(await getTemporaryDirectory()).path}/$path');
    await file.writeAsBytes(byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

    return file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      // You must wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner until the
      // controller has finished initializing.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return CameraPreview(_controller);
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;

            // Attempt to take a picture and get the file `image`
            // where it was saved.
            final image = await _controller.takePicture();

            // ML here
            // final RecognisedText recognisedText = await textDetector
            //     .processImage(InputImage.fromFilePath(image.path));

            final RecognisedText recognisedText = await textDetector
                .processImage(InputImage.fromFilePath(image.path));

            for (var block in recognisedText.blocks) {
              if (double.tryParse(block.text) != null) {
                timeStringDetected =
                    splitStringByLength(block.text, 2).join('.');
                break;
              }
            }

            // If the picture was taken, display it on a new screen.
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DisplayPictureScreen(
                  // Pass the automatically generated path to
                  // the DisplayPictureScreen widget.
                  imagePath: image.path,
                  recognizedString: timeStringDetected,
                ),
              ),
            );
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

// A widget that displays the picture taken by the user.
class DisplayPictureScreen extends StatefulWidget {
  final String imagePath;
  final String recognizedString;

  const DisplayPictureScreen(
      {Key? key, required this.imagePath, required this.recognizedString})
      : super(key: key);

  @override
  State<DisplayPictureScreen> createState() => _DisplayPictureScreenState();
}

class _DisplayPictureScreenState extends State<DisplayPictureScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      // The image is stored as a file on the device. Use the `Image.file`
      // constructor with the given path to display the image.
      body: Column(
        children: [
          Image.file(File(widget.imagePath)),
          Text(widget.recognizedString),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.save),
        onPressed: () async {
          if (widget.recognizedString != 'No valid time detected') {
            String? previousDataString = null;
            final prefs = await SharedPreferences.getInstance();
            List<dynamic> previousDataList = [];

            if (prefs.containsKey('timeData')) {
              previousDataString = prefs.getString('timeData');
              if (previousDataString != null) {
                previousDataList =
                    json.decode(previousDataString) as List<dynamic>;
              }
            }

            previousDataList.add({
              'date': DateTime.now().toIso8601String(),
              'timeTaken': widget.recognizedString,
            });

            final timeData = json.encode(previousDataList);

            await prefs.setString('timeData', timeData);
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DisplayResultsScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}

class DisplayResultsScreen extends StatefulWidget {
  const DisplayResultsScreen({Key? key}) : super(key: key);

  @override
  State<DisplayResultsScreen> createState() => _DisplayResultsScreenState();
}

class _DisplayResultsScreenState extends State<DisplayResultsScreen> {
  late SharedPreferences sharedPrefs;

  Future<List<dynamic>> _getPrefs() async {
    sharedPrefs = await SharedPreferences.getInstance();
    if (!sharedPrefs.containsKey('timeData')) {
      return [];
    } else {
      final prefData = sharedPrefs.getString('timeData');
      if (prefData == null) {
        return [];
      }

      final timeData = json.decode(prefData) as List<dynamic>;

      return timeData;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pass result')),
      body: FutureBuilder(
        future: _getPrefs(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Text(snapshot.data.toString());
          }
          return const CircularProgressIndicator(); // or some other widget
        },
      ),
    );
  }
}
