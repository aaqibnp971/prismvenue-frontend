import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Held for the app's life: it owns the AVAudioSession observers, and
  /// letting it deinit would silently stop the room ever being told a call
  /// had started.
  private var audioFocus: AudioFocusWatcher?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    audioFocus = AudioFocusWatcher(messenger: engineBridge.binaryMessenger)
  }
}
