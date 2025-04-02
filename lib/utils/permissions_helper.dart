import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<void> requestPermissions() async {
    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.photos,
      Permission.mediaLibrary,
      Permission.microphone,
      Permission.location,
      Permission.storage,
      Permission.camera,
      Permission.audio,
    ].request();
  }

  // Check if specific permissions are granted
  static Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  // Example: Check if microphone permission is granted
  static Future<bool> isMicrophonePermissionGranted() async {
    return await isPermissionGranted(Permission.microphone);
  }
}
