import Flutter
import UIKit
import AVFoundation
import linphonesw

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var numberSixBridge: NumberSixLinphoneBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NumberSixLinphoneBridge") else {
      print("[NumberSixLinphone] Could not create Flutter registrar")
      return
    }

    setupNumberSixBridge(messenger: registrar.messenger())
  }

  private func setupNumberSixBridge(messenger: FlutterBinaryMessenger) {
    if numberSixBridge != nil {
      return
    }

    numberSixBridge = NumberSixLinphoneBridge(messenger: messenger)
  }
}

final class NumberSixEventStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenCallback: (FlutterEventSink?) -> Void

  init(onListenCallback: @escaping (FlutterEventSink?) -> Void) {
    self.onListenCallback = onListenCallback
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    onListenCallback(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onListenCallback(nil)
    return nil
  }
}

final class NumberSixLinphoneBridge: NSObject {
  private var core: Core?
  private var coreDelegate: CoreDelegateStub?
  private var coreTimer: Timer?

  private var loginSink: FlutterEventSink?
  private var callSink: FlutterEventSink?

  private var currentDomain: String = "69.169.108.208"
  private var currentProxyHost: String = "sip.numbersixlimited.com"
  private var currentProxyPort: Int = 5061
  private var currentTransport: String = "tls"

  private var speakerEnabled = false

  init(messenger: FlutterBinaryMessenger) {
    super.init()

    let methodChannel = FlutterMethodChannel(name: "linphonesdk", binaryMessenger: messenger)

    let loginEventChannel = FlutterEventChannel(
      name: "linphonesdk/login_listener",
      binaryMessenger: messenger
    )

    let callEventChannel = FlutterEventChannel(
      name: "linphonesdk/call_event_listener",
      binaryMessenger: messenger
    )

    loginEventChannel.setStreamHandler(
      NumberSixEventStreamHandler { [weak self] sink in
        self?.loginSink = sink
      }
    )

    callEventChannel.setStreamHandler(
      NumberSixEventStreamHandler { [weak self] sink in
        self?.callSink = sink
      }
    )

    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    print("[NumberSixLinphone] Flutter channels ready")
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "request_permissions":
      requestPermissions(result: result)

    case "login":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "Missing login arguments", details: nil))
        return
      }

      let username = args["userName"] as? String ?? ""
      let password = args["password"] as? String ?? ""
      let domain = args["domain"] as? String ?? "69.169.108.208"
      let proxyHost = args["proxyHost"] as? String ?? domain
      let proxyPort = args["proxyPort"] as? Int ?? 5061
      let transport = args["transport"] as? String ?? "tls"

      login(
        username: username,
        password: password,
        domain: domain,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        transport: transport,
        result: result
      )

    case "call":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "Missing call arguments", details: nil))
        return
      }

      let number = args["number"] as? String ?? ""
      makeCall(number: number, result: result)

    case "hangUp", "hang_up":
      hangUp()
      result("Success")

    case "answerCall":
      answerCall()
      result("Success")

    case "rejectCall":
      rejectCall()
      result("Success")

    case "toggle_speaker", "toggleSpeaker":
      toggleSpeaker()
      result("Success")

    case "mute":
      result("Success")

    case "remove_listener", "remove_call_listener":
      result("Success")

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermissions(result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      result(granted ? "granted" : "denied")
    }
  }

  private func ensureCore() throws {
    if core != nil {
      return
    }

    linphonesw.LoggingService.Instance.logLevel = .Debug

    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    let configPath = libraryURL.appendingPathComponent("number_six_linphonerc").path

    let createdCore = try Factory.Instance.createCore(
      configPath: configPath,
      factoryConfigPath: "",
      systemContext: nil
    )

    coreDelegate = CoreDelegateStub(
      onCallStateChanged: { [weak self] _, _, state, message in
        let stateText = String(describing: state)
        print("[NumberSixLinphone] Call state: \(stateText) \(message)")
        self?.sendCallEvent(stateText)
      },
      onAccountRegistrationStateChanged: { [weak self] _, _, state, message in
        let stateText = String(describing: state)
        print("[NumberSixLinphone] Registration state: \(stateText) \(message)")
        self?.sendLoginEvent(stateText)
      }
    )

    if let delegate = coreDelegate {
      createdCore.addDelegate(delegate: delegate)
    }

    try createdCore.start()

    core = createdCore
    startCoreTimer()

    print("[NumberSixLinphone] Core started")
  }

  private func startCoreTimer() {
    coreTimer?.invalidate()

    coreTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
      self?.core?.iterate()
    }

    if let timer = coreTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func login(
    username: String,
    password: String,
    domain: String,
    proxyHost: String,
    proxyPort: Int,
    transport: String,
    result: @escaping FlutterResult
  ) {
    do {
      try ensureCore()

      guard let core = core else {
        result(FlutterError(code: "NO_CORE", message: "Linphone core not ready", details: nil))
        return
      }

      if username.isEmpty || password.isEmpty {
        result(FlutterError(code: "BAD_LOGIN", message: "Missing SIP username or password", details: nil))
        return
      }

      currentDomain = domain
      currentProxyHost = proxyHost
      currentProxyPort = proxyPort
      currentTransport = transport.lowercased()

      core.clearAllAuthInfo()
      core.clearAccounts()

      let authInfo = try Factory.Instance.createAuthInfo(
        username: username,
        userid: nil,
        passwd: password,
        ha1: nil,
        realm: nil,
        domain: domain
      )

      let accountParams = try core.createAccountParams()

      guard let identityAddress = core.interpretUrl(
        url: "sip:\(username)@\(domain)",
        applyInternationalPrefix: false
      ) else {
        result(FlutterError(code: "BAD_IDENTITY", message: "Invalid SIP identity", details: nil))
        return
      }

      let proxyUri = "sip:\(proxyHost):\(proxyPort);transport=\(currentTransport)"

      guard let proxyAddress = core.interpretUrl(
        url: proxyUri,
        applyInternationalPrefix: false
      ) else {
        result(FlutterError(code: "BAD_PROXY", message: "Invalid SIP proxy", details: proxyUri))
        return
      }

      try accountParams.setIdentityaddress(newValue: identityAddress)
      try accountParams.setServeraddress(newValue: proxyAddress)
      accountParams.registerEnabled = true

      let account = try core.createAccount(params: accountParams)

      core.addAuthInfo(info: authInfo)
      try core.addAccount(account: account)
      core.defaultAccount = account

      sendLoginEvent("Progress")

      print("[NumberSixLinphone] Registering \(username) domain=\(domain) proxy=\(proxyUri)")
      result("Success")
    } catch {
      print("[NumberSixLinphone] Login error: \(error)")
      sendLoginEvent("Failed")
      result(FlutterError(code: "LOGIN_ERROR", message: "\(error)", details: nil))
    }
  }

  private func makeCall(number: String, result: @escaping FlutterResult) {
    do {
      guard let core = core else {
        result(FlutterError(code: "NO_CORE", message: "Linphone core not ready", details: nil))
        return
      }

      let cleanNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)

      if cleanNumber.isEmpty {
        result(FlutterError(code: "BAD_NUMBER", message: "Number is empty", details: nil))
        return
      }

      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
      try audioSession.setActive(true)
      core.activateAudioSession(activated: true)

      let destination = "sip:\(cleanNumber)@\(currentDomain)"

      guard let remoteAddress = core.interpretUrl(
        url: destination,
        applyInternationalPrefix: false
      ) else {
        result(FlutterError(code: "BAD_DESTINATION", message: "Invalid destination", details: destination))
        return
      }

      let callParams = try core.createCallParams(call: nil)
      callParams.audioEnabled = true
      callParams.videoEnabled = false

      _ = core.inviteAddressWithParams(addr: remoteAddress, params: callParams)

      sendCallEvent("Dialing")
      print("[NumberSixLinphone] Calling \(destination)")
      result("Success")
    } catch {
      print("[NumberSixLinphone] Call error: \(error)")
      sendCallEvent("Error")
      result(FlutterError(code: "CALL_ERROR", message: "\(error)", details: nil))
    }
  }

  private func hangUp() {
    guard let core = core else {
      return
    }

    if let currentCall = core.currentCall {
      try? currentCall.terminate()
    }

    for call in core.calls {
      try? call.terminate()
    }

    sendCallEvent("End")
  }

  private func answerCall() {
    guard let call = core?.currentCall else {
      return
    }

    try? call.accept()
    sendCallEvent("Connected")
  }

  private func rejectCall() {
    guard let call = core?.currentCall else {
      return
    }

    try? call.terminate()
    sendCallEvent("End")
  }

  private func toggleSpeaker() {
    speakerEnabled.toggle()

    do {
      let session = AVAudioSession.sharedInstance()

      if speakerEnabled {
        try session.overrideOutputAudioPort(.speaker)
      } else {
        try session.overrideOutputAudioPort(.none)
      }

      print("[NumberSixLinphone] Speaker enabled: \(speakerEnabled)")
    } catch {
      print("[NumberSixLinphone] Speaker toggle error: \(error)")
    }
  }

  private func sendLoginEvent(_ value: String) {
    DispatchQueue.main.async { [weak self] in
      self?.loginSink?(value)
    }
  }

  private func sendCallEvent(_ value: String) {
    DispatchQueue.main.async { [weak self] in
      self?.callSink?(value)
    }
  }
}
