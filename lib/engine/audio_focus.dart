import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Something else is using the speakers."
///
/// The room should not play underneath a video call, a YouTube tab or a
/// walkthrough someone is watching on the same machine. On iOS and Android the
/// OS says so — an interrupted audio session, a revoked audio focus — but
/// **Windows has no such concept**: every process opens the shared mixer and
/// they all sound at once. So on Windows the signal is built by the runner,
/// which walks the default device's session list once a second and reports
/// whether any other process is actually emitting. See
/// `windows/runner/audio_focus.h` for why that is a poll and why it measures
/// the peak meter rather than trusting session state.
///
/// The same channel is the seam for the other platforms when they are wired:
/// they push rather than poll, but they answer the identical question, so
/// nothing above this line changes.
///
/// Silent no-op where nothing implements it — a dashboard on the web must not
/// fail because it cannot ask about speakers it does not have.
const MethodChannel audioFocusChannel = MethodChannel('prism/audio_focus');

/// True while another program is making an audible sound through the same
/// output device.
///
/// Starts false rather than unknown. The failure that matters is a room left
/// silent for a reason nobody can find, so an absent or broken watcher has to
/// mean "go ahead and play".
final externalAudioProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  controller.add(false);

  audioFocusChannel.setMethodCallHandler((call) async {
    if (call.method == 'externalAudioChanged' && !controller.isClosed) {
      controller.add(call.arguments as bool? ?? false);
    }
    return null;
  });

  ref.onDispose(() {
    audioFocusChannel.setMethodCallHandler(null);
    controller.close();
  });

  return controller.stream;
});
