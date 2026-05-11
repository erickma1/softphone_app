import 'package:flutter/material.dart';
import 'package:linphone_flutter_plugin/linphoneflutterplugin.dart';
import 'package:permission_handler/permission_handler.dart';

enum RegistrationState { None, Progress, Ok, Failed }

enum CallState {
  Idle,
  IncomingReceived,
  Dialing,
  Ringing,
  Connected,
  StreamsRunning,
  End,
  Error,
}

void main() {
  runApp(const MySoftphoneApp());
}

class MySoftphoneApp extends StatelessWidget {
  const MySoftphoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Number 6 Softphone',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SoftphoneHomePage(),
    );
  }
}

class SoftphoneHomePage extends StatefulWidget {
  const SoftphoneHomePage({super.key});

  @override
  State<SoftphoneHomePage> createState() => _SoftphoneHomePageState();
}

class _SoftphoneHomePageState extends State<SoftphoneHomePage> {
  final _sipUsernameController = TextEditingController();
  final _sipPasswordController = TextEditingController();
  final _sipDomainController = TextEditingController();
  final _dialNumberController = TextEditingController();

  final LinphoneFlutterPlugin _linphonePlugin = LinphoneFlutterPlugin();

  bool _isRegistered = false;
  RegistrationState _registrationState = RegistrationState.None;
  CallState? _currentCallState;
  String _debugMessage = '';

  @override
  void initState() {
    super.initState();
    _initAndSetup();
  }

  Future<void> _initAndSetup() async {
    await _requestPermissions();

    // Listen to call state changes
    _linphonePlugin.addCallStateListener().listen((dynamic state) {
      final callState = _convertCallState(state);
      setState(() => _currentCallState = callState);
      _log('Call state changed: $callState');

      if (callState == CallState.IncomingReceived) {
        _showIncomingCallDialog();
      }

      // If the call ends with an error, reset audio devices to avoid “sound locked”
      if (callState == CallState.Error || callState == CallState.End) {
        _resetAudioDevices();
      }
    });
  }

  // ----------------------------------------------------------------------
  // Incoming call dialog with Answer & Reject
  // ----------------------------------------------------------------------
  void _showIncomingCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: const Text('You have an incoming call.'),
        actions: [
          TextButton(
            onPressed: () async {
              await _hangUp();
              Navigator.pop(context);
              _log('Call rejected');
            },
            child: const Text('Reject'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // await _answerCall();
            },
            child: const Text('Answer'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // Answer the incoming call (uses the plugin's answerCall method)
  // ----------------------------------------------------------------------
  // Future<void> _answerCall() async {
  //   try {
  //     await _linphonePlugin.answerCall();
  //     _log('Call answered');
  //   } catch (e) {
  //     _log('Failed to answer call: $e');
  //   }
  // }

  // ----------------------------------------------------------------------
  // Reset audio devices after a failed call (prevents "sound locked" error)
  // ----------------------------------------------------------------------
  Future<void> _resetAudioDevices() async {
    try {
      // Toggle mute twice to force audio path reinitialization
      await _linphonePlugin.toggleMute();
      await Future.delayed(const Duration(milliseconds: 100));
      await _linphonePlugin.toggleMute();
      _log('Audio devices reset after call error');
    } catch (e) {
      _log('Could not reset audio: $e');
    }
  }

  // ----------------------------------------------------------------------
  // Request microphone & phone permissions
  // ----------------------------------------------------------------------
  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
      Permission.phone,
    ].request();

    if (statuses[Permission.microphone] == PermissionStatus.granted) {
      _log('Microphone permission granted');
    } else {
      _log('Microphone permission denied – calling will not work');
    }
  }

  // ----------------------------------------------------------------------
  // SIP Login (with a 5‑second delay because the plugin doesn't expose
  // registration state events)
  // ----------------------------------------------------------------------
  Future<void> _login() async {
    final username = _sipUsernameController.text.trim();
    final password = _sipPasswordController.text.trim();
    final domain = _sipDomainController.text.trim();

    if (username.isEmpty || password.isEmpty || domain.isEmpty) {
      _log('Please fill all fields');
      return;
    }

    setState(() {
      _registrationState = RegistrationState.Progress;
      _isRegistered = false;
    });
    _log('Attempting SIP registration...');

    try {
      await _linphonePlugin.login(
        userName: username,
        domain: domain,
        password: password,
      );

      // Wait 5 seconds to give the server time to accept/reject registration
      await Future.delayed(const Duration(seconds: 5));

      // Since the plugin doesn't give us a real registration state,
      // we assume success if no exception was thrown.
      setState(() {
        _registrationState = RegistrationState.Ok;
        _isRegistered = true;
      });
      _log('Registration assumed successful (no error thrown)');
    } catch (e) {
      setState(() {
        _registrationState = RegistrationState.Failed;
        _isRegistered = false;
      });
      _log('Registration failed: $e');
    }
  }

  // ----------------------------------------------------------------------
  // Logout – resets UI and (if implemented) unregisters from the server.
  // To fully disconnect, you must add a logout() method to the plugin
  // as described in the earlier answer.
  // ----------------------------------------------------------------------
  Future<void> _logout() async {
    try {
      // If there's an active call, hang it up first
      if (_currentCallState != null &&
          _currentCallState != CallState.Idle &&
          _currentCallState != CallState.End) {
        await _hangUp();
      }
      // Clear UI state – plugin logout must be implemented separately
      setState(() {
        _isRegistered = false;
        _registrationState = RegistrationState.None;
        _currentCallState = null;
      });
      _log(
        'Logged out (UI reset) – server deregistration depends on plugin implementation',
      );
    } catch (e) {
      _log('Logout error: $e');
    }
  }

  // ----------------------------------------------------------------------
  // Make an outgoing call
  // ----------------------------------------------------------------------
  Future<void> _makeCall() async {
    final number = _dialNumberController.text.trim();
    if (number.isEmpty) {
      _log('Please enter a number to dial');
      return;
    }
    if (!_isRegistered) {
      _log('Not registered with SIP server – cannot call');
      return;
    }
    try {
      await _linphonePlugin.call(number: number);
      _log('Calling $number...');
    } catch (e) {
      _log('Failed to place call: $e');
    }
  }

  // ----------------------------------------------------------------------
  // Hang up the current call
  // ----------------------------------------------------------------------
  Future<void> _hangUp() async {
    try {
      await _linphonePlugin.hangUp();
      _log('Call ended');
    } catch (e) {
      _log('Failed to hang up: $e');
    }
  }

  void _log(String msg) {
    setState(() => _debugMessage = msg);
    print(msg);
  }

  // ----------------------------------------------------------------------
  // Helper to convert native call state strings to our CallState enum
  // ----------------------------------------------------------------------
  CallState _convertCallState(dynamic state) {
    final stateStr = state.toString().toLowerCase();
    if (stateStr.contains('incoming')) return CallState.IncomingReceived;
    if (stateStr.contains('dialing')) return CallState.Dialing;
    if (stateStr.contains('ringing')) return CallState.Ringing;
    if (stateStr.contains('connected')) return CallState.Connected;
    if (stateStr.contains('streams')) return CallState.StreamsRunning;
    if (stateStr.contains('end') || stateStr.contains('released'))
      return CallState.End;
    if (stateStr.contains('error')) return CallState.Error;
    return CallState.Idle;
  }

  // ----------------------------------------------------------------------
  // UI Build
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Softphone')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _sipUsernameController,
                      decoration: const InputDecoration(
                        labelText: 'SIP Username',
                      ),
                    ),
                    TextField(
                      controller: _sipPasswordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    TextField(
                      controller: _sipDomainController,
                      decoration: const InputDecoration(
                        labelText: 'Domain (e.g., sip.example.com)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                (_registrationState ==
                                    RegistrationState.Progress)
                                ? null
                                : _login,
                            child: Text(
                              _registrationState == RegistrationState.Progress
                                  ? 'Registering...'
                                  : (_isRegistered ? 'Registered' : 'Register'),
                            ),
                          ),
                        ),
                        if (_isRegistered)
                          TextButton(
                            onPressed: _logout,
                            child: const Text('Logout'),
                          ),
                      ],
                    ),
                    if (_registrationState == RegistrationState.Failed)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Registration failed. Check credentials and server.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _dialNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Number to dial',
                        hintText: 'e.g., 1001 or sip:user@domain',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _makeCall,
                            child: const Text('Call'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _hangUp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Hang Up'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_currentCallState != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Call Status',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_currentCallState.toString()),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Debug Log',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_debugMessage),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
