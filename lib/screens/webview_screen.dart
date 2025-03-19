import 'package:caltondatx/utils/permissions_helper.dart';
import 'package:caltondatx/widgets/loading_animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:io';
import 'package:printing/printing.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late InAppWebViewController webViewController;
  RefreshController pullToRefreshController = RefreshController(initialRefresh: false);

  bool _permissionsGranted = false;
  bool _showSplash = true;
  int _progress = 0;
  bool _webViewLoaded = false;
  bool _jsSystemLoadReceived = false;


  final String webUrl = "https://beta.caltondatx.com";

 @override
  void initState() {
    super.initState();
  
    _requestPermissions();
    //checkAndRequestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      await PermissionHelper.requestPermissions();
      if (mounted) {
        setState(() {
          _permissionsGranted = true;
        });
      }
    } catch (e) {
      debugPrint("Permission error: $e");
    }
  }

 /*  void checkAndRequestPermissions() async {
    await PermissionHelper.requestPermissions();
  } */

  Future<void> _onRefresh() async {
    await webViewController.reload();
    pullToRefreshController.refreshCompleted();
  }
  
  Future<void> _injectViewportAndPrintHandler(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: """
      var metas = document.getElementsByTagName('meta');
      for (var i = metas.length - 1; i >= 0; i--) {
        if (metas[i].name === "viewport") {
          metas[i].parentNode.removeChild(metas[i]);
        }
      }
      var meta = document.createElement('meta');
      meta.name = "viewport";
      meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no";
      document.getElementsByTagName('head')[0].appendChild(meta);

      document.addEventListener('gesturestart', function(e){e.preventDefault();});
      document.addEventListener('gesturechange', function(e){e.preventDefault();});
      document.addEventListener('gestureend', function(e){e.preventDefault();});

      window.print = function() {
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('print', document.documentElement.outerHTML);
        } else {
          console.log('window.flutter_inappwebview not found');
        }
      };
    """);
  }

  // Function to pick the save directory
  Future<String?> pickSaveDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    return result;  // Return selected directory or null
  }

  // Function to get file extension from mime type
  String? extensionFromMime(String mimeType) {
    final mimeMap = {
      'application/pdf': 'pdf',
      'text/csv': 'csv',
      'image/png': 'png',
    };
    return mimeMap[mimeType] ?? 'bin';
  }

  // Function to inject JavaScript for handling button click in WebView
  void _injectSpeechRecognitionJs() {
    final script = """
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (SpeechRecognition) {
        const recognition = new SpeechRecognition();
        recognition.continuous = false;
        recognition.interimResults = false;
        recognition.lang = 'en-US';

        recognition.onstart = () => {
          console.log('Speech recognition started');
        };

        recognition.onend = () => {
          console.log('Speech recognition ended');
        };

        recognition.onresult = (event) => {
          const transcript = event.results[0][0].transcript;
          window.flutter_inappwebview.callHandler('onSpeechResult', transcript);
        };

        recognition.onerror = (event) => {
          console.error('Speech recognition error:', event.error);
          window.flutter_inappwebview.callHandler('onSpeechError', event.error);
        };

      } else {
        alert('Speech recognition is not supported in this browser.');
      }
    """;
    webViewController.evaluateJavascript(source: script);
  }

  Future<void> _handleDownloadStartRequest(String downloadUrl) async {
    try {
      if (downloadUrl.startsWith("blob:")) {
        await webViewController.evaluateJavascript(source: """
          if (!window._csvDownloadIntercepted) {
            window._csvDownloadIntercepted = true;
            document.addEventListener('click', function(event) {
              const target = event.target;
              if (target.tagName === 'A' && target.download && target.href.startsWith('blob:')) {
                const filename = target.download;
                const href = target.href;
                fetch(href).then(response => response.blob()).then(blob => {
                  const reader = new FileReader();
                  reader.onloadend = function () {
                    const base64Data = reader.result.split(',')[1];
                    if (window.flutter_inappwebview) {
                      window.flutter_inappwebview.callHandler('onCSVDownloadBlob', {
                        filename: filename,
                        base64: reader.result,
                        mimeType: blob.type
                      });
                    }
                  };
                  reader.readAsDataURL(blob);
                });
                event.preventDefault();
              }
            }, true);
          }
          """);
        } else if (downloadUrl.startsWith("data:image/png;base64,")) {
            try {

                final base64Str = downloadUrl.split(',').last;
                final bytes = base64Decode(base64Str);
                final mimeType = lookupMimeType('', headerBytes: bytes);
                final fileExt = extensionFromMime(mimeType ?? '') ?? 'png';

                final fileName = "caltonDatx_download_image_${DateTime.now().millisecondsSinceEpoch}.$fileExt";
                final saveDirectory = await FilePicker.platform.getDirectoryPath();

                String finalPath = saveDirectory ?? (await getDownloadsDirectory())?.path ?? '';

                  if (finalPath.isEmpty) {
                    debugPrint("❌ Could not get valid save location.");
                    return;
                  }

                final filePath = path.join(finalPath, fileName);
                final file = File(filePath);
                  
                  await file.writeAsBytes(bytes);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ File downloaded: $fileName')),
                    );
                    await OpenFile.open(file.path);
                  }

                } catch (e) {
                  if (kDebugMode) {
                    print("❌ Error saving base64 image: $e");
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('❌ Failed to download image')),
                    );
                  }
                }
              }
          } catch (e) {
            debugPrint("Download error: $e");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('❌ Download failed: $e')),
              );
            }
          }

          await webViewController.evaluateJavascript(source: """
            var metas = document.getElementsByTagName('meta');
            for (var i = metas.length - 1; i >= 0; i--) {
              if (metas[i].name === "viewport") {
                metas[i].parentNode.removeChild(metas[i]);
              }
            }
            var meta = document.createElement('meta');
            meta.name = "viewport";
            meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no";
            document.getElementsByTagName('head')[0].appendChild(meta);
            """);

          await webViewController.evaluateJavascript(source: """
            window.print = function() {
              window.flutter_inappwebview.callHandler('Print', document.documentElement.outerHTML);
            };
            """);
  }

  void _setUpJavaScriptHandlers() {
    // Handler for blob downloads
    webViewController.addJavaScriptHandler(
      handlerName: 'blobDownload',
      callback: (args) async {
        try {
          final base64DataUrl = args[0] as String;
          final mimeType = args[1] as String;
          final customTitle = args.length > 2 ? args[2] as String : 'downloaded_file';
          final base64Data = base64DataUrl.split(',').last;
          final bytes = base64Decode(base64Data);
          final extension = extensionFromMime(mimeType);
          final sanitizedTitle = customTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final fileName = "$sanitizedTitle.${extension ?? 'bin'}";

          // Ask user to pick save directory
          final saveDirectory = await pickSaveDirectory();
          if (saveDirectory != null) {
            final filePath = path.join(saveDirectory, fileName);
            final file = File(filePath);
            await file.writeAsBytes(bytes);

            debugPrint("Blob file saved at: $filePath");
            await OpenFile.open(file.path);
          }
        } catch (e) {
          debugPrint("Blob download error: $e");
        }
      },
    );

    // Handler for CSV downloads
    webViewController.addJavaScriptHandler(
      handlerName: 'onCSVDownloadBlob',
      callback: (args) async {
        try {
          final data = args[0];
          final filename = data['filename'];
          final base64 = data['base64'];
          final mimeType = data['mimeType'];
          final base64Data = base64.split(',').last;
          final bytes = base64Decode(base64Data);

          // Ensure the filename has the correct extension based on MIME type
          String? extension = extensionFromMime(mimeType);
          String finalFilename = filename;

          // If the file name doesn't have an extension, append it
          if (!finalFilename.contains(".")) {
            finalFilename = "$finalFilename.$extension";
          }

          // Ask user to pick save directory
          final saveDirectory = await pickSaveDirectory();
          if (saveDirectory != null) {
            final filePath = path.join(saveDirectory, finalFilename);
            final file = File(filePath);
            await file.writeAsBytes(bytes);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("✅ Downloaded: $finalFilename")),
              );
              await OpenFile.open(file.path);
            }
            debugPrint("File saved at: $filePath");
          }
        } catch (e) {
          debugPrint("CSV Download error: $e");
        }
      },
    );

    // Handler for base64 file download
    webViewController.addJavaScriptHandler(
      handlerName: 'downloadBase64File',
      callback: (args) async {
        try {
          final data = args[0];
          final base64 = data['base64'] as String;
          final filename = data['filename'] as String? ?? 'downloaded_file.pdf';
          final mimeType = data['mimeType'] as String? ?? 'application/pdf';

          final bytes = base64Decode(base64);
          extensionFromMime(mimeType);

          // Ask user to pick save directory
          final saveDirectory = await pickSaveDirectory();
          if (saveDirectory != null) {
            final sanitizedFilename = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
            final filePath = path.join(saveDirectory, sanitizedFilename);
            final file = File(filePath);
            await file.writeAsBytes(bytes);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("✅ Downloaded: $filename")),
              );
            }
            await OpenFile.open(file.path);
          }
        } catch (e) {
          debugPrint("PDF Download error: $e");
          if (context.mounted) {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("❌ Failed to download PDF")),
            );
          }
        }
      },
    );
  }

  void _printHandler() {
    webViewController.addJavaScriptHandler(
    handlerName: "print",
    callback: (args) async {
        final htmlContent = args[0]['html'];
        debugPrint("✅ PRINT HANDLER TRIGGERED!");
        debugPrint("htmlContent: $htmlContent");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Print Handler Triggered")),
        );

        await Printing.layoutPdf(
          onLayout: (format) async {
            // ignore: deprecated_member_use
            return await Printing.convertHtml(
              format: format,
              html: htmlContent,
            );
          },
        );

        return {'status': 'printed'};
      },
    );
  }

  void _addJavaScriptHandlers() {
    webViewController.addJavaScriptHandler(
      handlerName: 'onSpeechResult',
      callback: (args) {
        String transcript = args[0];
        debugPrint("Speech Recognized: $transcript");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Speech recognized: $transcript"),
        ));
      },
    );

    webViewController.addJavaScriptHandler(
      handlerName: 'onSpeechError',
      callback: (args) {
        String error = args[0];
        debugPrint("Speech Recognition Error: $error");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Speech recognition error: $error"),
        ));
      },
    );
  }

 

   Widget _buildSplashOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/splash.png', fit: BoxFit.cover),
            ),
            const Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(child: LoadingTextAnimation()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return Offstage(
      offstage: !_permissionsGranted,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(webUrl)),
        initialSettings: InAppWebViewSettings(
          useHybridComposition: true,
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          builtInZoomControls: false,
          displayZoomControls: false,
          supportZoom: false,
          allowFileAccess: true,
          disableContextMenu: true,

        ),
        onWebViewCreated: (controller) {
          webViewController = controller;
          _injectViewportAndPrintHandler(controller);
        },
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
        },

        onLoadStop: (controller, url) async {
          await _injectViewportAndPrintHandler(controller);
          pullToRefreshController.refreshCompleted();
          //setState(() => _showSplash = false);
        },
        onLoadError: (controller, url, code, message) {
          pullToRefreshController.refreshFailed();
        },
        onProgressChanged: (controller, progress) {
          setState(() {
            _progress = progress;
            if (progress >= 100) {
             _webViewLoaded = true;
            pullToRefreshController.refreshCompleted();
            _maybeHideSplash();
            }
          });
        },
        // ignore: deprecated_member_use
        androidOnPermissionRequest: (controller, origin, resources) async {
          // ignore: deprecated_member_use
          return PermissionRequestResponse(
            resources: resources,
            // ignore: deprecated_member_use
            action: PermissionRequestResponseAction.GRANT,
          );
        },
        onDownloadStartRequest: (controller, url) async {
          await _handleDownloadStartRequest(url.url.toString());
        },
        onConsoleMessage: (controller, consoleMessage) async {
          debugPrint("Console Log: ${consoleMessage.message}");

          if (consoleMessage.message.contains("Speech Recognition Error: not-allowed")) {
            await Permission.microphone.request();
          }

          if (consoleMessage.message.contains("System Load")) {
          setState(() {
            _jsSystemLoadReceived = true;
            _maybeHideSplash();
          });
        }
        },
      ),
    );
  }

 void _maybeHideSplash() {
    if (_webViewLoaded && _jsSystemLoadReceived) {
      setState(() {
        _showSplash = false;
      });
    }
  }
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SmartRefresher(
              controller: pullToRefreshController,
              onRefresh: _onRefresh,
              enablePullDown: true,
              child: _buildWebView(),
            ),
          ),
          if (_showSplash || !_permissionsGranted) 
           AnimatedOpacity(
              opacity: _showSplash || !_permissionsGranted ? 1.0 : 0.0,
              duration: Duration(milliseconds: 300), // Adjust duration for smooth fade
              child: _buildSplashOverlay(),
      ),

          // if (_progress < 100)
          //   Positioned(
          //     top: 0,
          //     left: 0,
          //     right: 0,
          //     child: LinearProgressIndicator(value: _progress / 100),
          //   ),git commit -m "first commit"
        ],
      ),
    );
  }
}



