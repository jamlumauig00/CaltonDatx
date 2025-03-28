import 'package:caltondatx/utils/permissions_helper.dart';
import 'package:caltondatx/widgets/loading_animation.dart';
import 'package:dashed_circular_progress_bar/dashed_circular_progress_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_file/open_file.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:io';
import 'package:printing/printing.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late InAppWebViewController webViewController;
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  bool _permissionsGranted = false;
  bool _showSplash = true;
  bool _webViewLoaded = false;
  bool _jsSystemLoadReceived = false;

// Track the downward drag offset (in pixels)
  double _dragOffset = 0.0;
  // Set a threshold for triggering refresh
  final double _dragThreshold = 80.0;

  // Track the current vertical scroll offset of the web view
  double _webViewScrollOffset = 0.0;
  bool _isRefreshing = false;

  bool pullToRefreshEnabled = true;
  final String webUrl = "https://beta.caltondatx.com";

 @override
  void initState() {
    super.initState();
  
    _requestPermissions();

    
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

 /*  Future<void> _onRefresh() async {
    await webViewController.reload();
    pullToRefreshController.refreshCompleted();
  } */

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    // Reload the WebView
    await webViewController.reload();
    // Wait a bit for content to load (adjust as needed)
    await Future.delayed(const Duration(seconds: 2));
    _refreshController.refreshCompleted();
    setState(() {
      _isRefreshing = false;
    });
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
      if (kDebugMode) { print("❌ downloadUrl: $downloadUrl");} 
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
    // Handler for CSV downloads
      webViewController.addJavaScriptHandler(
      handlerName: 'onCSVHandler',
      callback: (args) async {
        try {
          debugPrint("✅ Received data 3 from JavaScript: $args");

           final Map<String, dynamic>? data = args[0] as Map<String, dynamic>?;
            if (data == null) throw Exception("Received null data");
            final filename = args[0]['filename'];
            debugPrint("✅ Received filename1 from JavaScript: $filename");

            final String? csvContent = data['content'] as String?;
            if (csvContent == null || csvContent.isEmpty) {
              throw Exception("CSV content is empty");
            }
            final bytes = utf8.encode(csvContent); // Convert CSV content to bytes
            String? savePath;

            if (Platform.isAndroid) {
              // 📌 Ask Android user where to save the file
              savePath = await FilePicker.platform.getDirectoryPath();

              if (savePath != null) {
                savePath = "$savePath/$filename";
              } else {
                // Default to Downloads folder if user doesn't pick a location
                savePath = "/storage/emulated/0/Download/$filename";
              }
            } 
            else if (Platform.isIOS) {
              // 📌 iOS: Save to app's documents directory
              Directory directory = await getApplicationDocumentsDirectory();
              savePath = "${directory.path}/$filename";
            }

            // Ensure savePath is valid
            if (savePath == null) {
              debugPrint("❌ No valid save path found.");
              return;
            }

            // Check if file already exists and get a unique filename if necessary
            savePath = getUniqueFileName(savePath);

            File file = File(savePath);
            await file.writeAsBytes(bytes);
            debugPrint("✅ File saved at: $savePath");

            // Open the saved file
            await OpenFile.open(file.path);
          } catch (e) {
            debugPrint("❌ Error saving file: $e");
          }
        } 
          );   

      // 📌 JavaScript handler to receive PNG data
          webViewController.addJavaScriptHandler(
            handlerName: 'onPNGHandler',
            callback: (args) async {
              try {
                if (args.isEmpty) {
                  debugPrint("❌ No data received.");
                  return;
                }

                final data = args[0];
                final base64String = data['base64'];

                if (base64String == null || !base64String.contains(',')) {
                  debugPrint("❌ Invalid Base64 data.");
                  return;
                }

                // Extract only the Base64 image data (remove 'data:image/png;base64,')
                final base64Data = base64String.split(',').last;
                final bytes = base64Decode(base64Data);

                // Determine file name
                final fileName = data['filename'] ?? "downloaded_image.png";

                // 📌 Save file based on platform
                if(Platform.isAndroid){
                  final saveDirectory = await FilePicker.platform.getDirectoryPath();
                  String finalPath = saveDirectory ?? (await getDownloadsDirectory())?.path ?? '';

                  if (finalPath.isEmpty) {
                    debugPrint("❌ Could not get valid save location.");
                    return;
                  }
                    final filePath = path.join(finalPath, fileName);
                    final file = File(filePath);
                    await file.writeAsBytes(bytes);
                    await OpenFile.open(file.path);
                }else if(Platform.isIOS){
                    Directory directory = await getApplicationCacheDirectory();
                    String filePath = '${directory.path}/$fileName';
                    File file = File(filePath);
                    await file.writeAsBytes(bytes);

                    debugPrint("✅ PNG saved at: $filePath");

                    // Open the file (optional)
                    await OpenFile.open(filePath);
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
            },
          );
 
    // Handler for PDF file download
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

          if (Platform.isAndroid){
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
          }else {
          Directory directory = await getApplicationDocumentsDirectory();
          String filePath = path.join(directory.path, filename);
          File file = File(filePath);
          await file.writeAsBytes(bytes);      
         
          /* if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("✅ Downloaded: $filename")),
              );
              await OpenFile.open(file.path, type: "application/pdf");
            } */
          await OpenFile.open(file.path, type: "application/pdf");

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
    return Stack( // ✅ Correct: Wrap Positioned inside a Stack
    children: [
      Positioned.fill(
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
    ),
    ],
    );
  }

  Widget _buildWebView() {
    return Offstage(
      offstage: !_permissionsGranted,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(webUrl)),
        // ignore: deprecated_member_use
        initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          mediaPlaybackRequiresUserGesture: false,
           disableHorizontalScroll: false,
           disableVerticalScroll: false, // Ensure scrolling is enabled
           supportZoom: false,
          //allowsInlineMediaPlayback: true,
        ),
        ios: IOSInAppWebViewOptions(
          allowsBackForwardNavigationGestures: true,
          isPagingEnabled: false,  // Ensures better scrolling behavior
          allowsInlineMediaPlayback: true,
          allowsAirPlayForMediaPlayback: true,
          scrollsToTop: true
          
        ),
      ),  
        onPermissionRequest: (controller, request) async {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.GRANT,
          );
        },
        initialSettings: InAppWebViewSettings(
          allowsBackForwardNavigationGestures: true, // Enables swipe gestures in iOS
          isInspectable: true,
          disallowOverScroll: false,
          cacheEnabled: true, 
          useShouldInterceptRequest: false, // Allow WebView to manage caching
          useOnLoadResource: true, 
          useHybridComposition: true,
          javaScriptEnabled: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          //javascriptMode: JavascriptMode.unrestricted, // Enable JavaScript
          allowsInlineMediaPlayback: true,
          allowsLinkPreview : false,
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
          _setUpJavaScriptHandlers();
          _addJavaScriptHandlers();
          _printHandler();
          _injectSpeechRecognitionJs();
        },
       gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },          
        onLoadStop: (controller, url) async {
          _refreshController.refreshCompleted();
          await _injectViewportAndPrintHandler(controller);
          //setState(() => _showSplash = false);
        },

        onLoadError: (controller, url, code, message) {
          _refreshController.refreshFailed();
        },
         onReceivedError: (controller, request, error) {
              //pullToRefreshController2?.endRefreshing();
            },
            onScrollChanged: (controller, x, y) {
            setState(() {
              _webViewScrollOffset = y.toDouble();
            });
          },

        onProgressChanged: (controller, progress) {
          setState(() {
            if (progress >= 100) {
             _webViewLoaded = true;
            _refreshController.refreshCompleted();
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
      body: SafeArea(
        bottom: false, // Bottom safe area disabled
        child: Stack(
          children: [
            // WebView fills the screen and scrolls normally.
            Positioned.fill(
              child: _buildWebView(),
            ),
            // Overlay GestureDetector only active when WebView is scrolled near top.
            if (_webViewScrollOffset <= 10)
              Positioned(
                top: 0,
                left: 50,
                right:150,
                height: 150, // Detection area at the top
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy > 0) {
                      setState(() {
                        _dragOffset += details.delta.dy;
                      });
                    }
                  },
                  onVerticalDragEnd: (details) {
                    if (_dragOffset >= _dragThreshold) {
                      _onRefresh();
                    }
                    setState(() {
                      _dragOffset = 0.0;
                    });
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            // Optional refresh indicator overlay.
            if (_isRefreshing)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: DashedCircularProgressBar.square(
                    dimensions: 50,
                    progress: 50,
                    maxProgress: 50,
                    startAngle: 0,
                    foregroundColor: Color(0xFF183465),
                    backgroundColor: const Color(0xffeeeeee),
                    foregroundStrokeWidth: 7,
                    backgroundStrokeWidth: 7,
                    foregroundGapSize: 5,
                    foregroundDashSize: 40,
                    backgroundGapSize: 5,
                    backgroundDashSize: 40,
                    animation: true,
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 20
                    ),
                  )
                ),
              ),
          ],
        ),
      ),
    );
  }

  String getUniqueFileName(String filePath) {
      File file = File(filePath);
      if (!file.existsSync()) return filePath; // If file doesn't exist, use original path

      String dir = file.parent.path;
      String name = file.uri.pathSegments.last;
      String baseName = name.replaceAll(RegExp(r'\.csv$'), ''); // Remove .csv extension
      int count = 1;

      // Loop until we find a unique fiSlename
      while (file.existsSync()) {
        filePath = "$dir/$baseName ($count).csv";
        file = File(filePath);
        count++;
      }
      return filePath;
  }
}

