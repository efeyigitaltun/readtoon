/// Compatibility wrapper for legacy setup flows.
///
/// Directory access is granted per selected folder by Android's Storage Access
/// Framework; ReadToon does not request broad storage permissions.
class PermissionService {
  const PermissionService();

  Future<bool> requestStoragePermission() async => true;

  Future<bool> isStoragePermissionGranted() async => true;

  Future<bool> isPermanentlyDenied() async => false;

  Future<void> openAppPermissionSettings() async {}
}
