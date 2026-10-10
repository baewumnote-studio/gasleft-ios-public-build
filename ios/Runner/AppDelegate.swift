// GasLeft AppDelegate for Flutter 3.47+ / UIScene lifecycle.
// Checked against Flutter UIScene migration guidance and
// flutter_local_notifications 22.3.1 on 2026-10-07.
//
// Purpose:
// 1) Configure UNUserNotificationCenter.delegate before launch completes.
// 2) Register Flutter plugins through FlutterImplicitEngineDelegate so the
//    project remains compatible with the UIScene lifecycle required by Xcode 27.

import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
