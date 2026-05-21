/// Splash kiosk form copy (Sonar S3358 extraction).
String appSplashKioskSubtitle({
  required bool manageKiosk,
  required bool needsEntry,
}) {
  if (manageKiosk) return 'Kiosk settings';
  if (needsEntry) return 'Enter your venue kiosk code to continue';
  return 'Getting things ready…';
}
