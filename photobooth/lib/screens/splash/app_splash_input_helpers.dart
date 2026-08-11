/// Whether the splash full-screen busy barrier should block interaction.
///
/// When the kiosk-code form is visible, never cover the field — Continue can
/// still show an inline spinner. Auto-verify of a stored code (no form yet)
/// may use the barrier.
bool splashShouldBlockWithBusyOverlay({
  required bool busy,
  required bool showForm,
}) {
  return busy && !showForm;
}

/// Whether the kiosk code [CupertinoTextField] may accept typing.
///
/// Always true while the entry form is shown so a slow verify cannot freeze
/// the field (`enabled: false` + barrier felt “stuck while typing”).
bool splashCodeFieldEnabled({
  required bool busy,
  required bool showForm,
}) {
  if (showForm) return true;
  return !busy;
}
