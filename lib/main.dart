import 'package:flutter/material.dart';
import 'package:linphone_flutter_plugin/linphoneflutterplugin.dart';
import 'package:permission_handler/permission_handler.dart';

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

// Model for call log entries
class CallLogEntry {
  final String number;
  final String status; // 'Connected', 'Missed', 'Outgoing'
  final DateTime date;
  final int duration; // in seconds

  CallLogEntry({
    required this.number,
    required this.status,
    required this.date,
    required this.duration,
  });
}

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

class SoftphoneHomePage extends StatefulWidget {
  const SoftphoneHomePage({super.key});

  @override
  State<SoftphoneHomePage> createState() => _SoftphoneHomePageState();
}

class _SoftphoneHomePageState extends State<SoftphoneHomePage> {
  final LinphoneFlutterPlugin _linphonePlugin = LinphoneFlutterPlugin();
  int _selectedIndex = 0; // 0: Dialer, 1: Call Log, 2: Settings

  // SIP settings
  final _sipUsernameController = TextEditingController();
  final _sipPasswordController = TextEditingController();
  final _sipDomainController = TextEditingController();
  bool _isRegistered = false;
  RegistrationState _registrationState = RegistrationState.None;
  String _registrationError = '';

  // Dialer state
  final _dialNumberController = TextEditingController();
  CallState? _currentCallState;
  String _debugMessage = '';

  // Local call log
  List<CallLogEntry> _callLogs = [];
  DateTime? _callStartTime;
  String? _lastDialedNumber;
  bool _isIncomingCall = false;
  String? _incomingNumber;

  @override
  void initState() {
    super.initState();
    _initAndSetup();
    _loadStoredCredentials();
  }

  Future<void> _loadStoredCredentials() async {
    // Optional: use shared_preferences to load saved credentials
  }

  Future<void> _initAndSetup() async {
    await _requestPermissions();

    _linphonePlugin.addCallStateListener().listen((dynamic state) {
      final callState = _convertCallState(state);
      setState(() => _currentCallState = callState);
      _log('Call state changed: $callState');

      if (callState == CallState.IncomingReceived) {
        _showIncomingCallDialog();
      }

      // Track call start and end for local logs
      if (callState == CallState.Connected && _callStartTime == null) {
        _callStartTime = DateTime.now();
        _log('Call started at ${_callStartTime}');
      }

      if (callState == CallState.End || callState == CallState.Error) {
        if (_callStartTime != null && _lastDialedNumber != null) {
          final duration = DateTime.now().difference(_callStartTime!).inSeconds;
          _addCallLog(
            number: _lastDialedNumber!,
            status: 'Outgoing',
            date: _callStartTime!,
            duration: duration,
          );
          _callStartTime = null;
          _lastDialedNumber = null;
        } else if (_isIncomingCall && _incomingNumber != null) {
          // Incoming call was answered – we would have set _callStartTime earlier
          // but if not, we still log as missed or answered?
          // For simplicity, we only log answered outgoing calls.
          // You can expand this.
          _isIncomingCall = false;
          _incomingNumber = null;
        }
        _resetAudioDevices();
      }
    });
  }

  void _addCallLog({
    required String number,
    required String status,
    required DateTime date,
    required int duration,
  }) {
    setState(() {
      _callLogs.insert(
        0,
        CallLogEntry(
          number: number,
          status: status,
          date: date,
          duration: duration,
        ),
      );
      // Keep only last 100 logs
      if (_callLogs.length > 100) _callLogs.removeLast();
    });
  }

  void _showIncomingCallDialog() {
    // For incoming calls, we could set _incomingNumber from call details.
    // Since the plugin may not provide it easily, we'll just show the dialog.
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
              _isIncomingCall = true;
              _callStartTime = DateTime.now();
              // The number would be obtained from call object; for now we use placeholder
              _incomingNumber = 'Incoming';
              _log('Call answered');
            },
            child: const Text('Answer'),
          ),
        ],
      ),
    );
  }

  // Future<void> _answerCall() async {
  //   try {
  //     await _linphonePlugin.answerCall();
  //   } catch (e) {
  //     _log('Failed to answer call: $e');
  //   }
  // }

  Future<void> _resetAudioDevices() async {
    try {
      await _linphonePlugin.toggleMute();
      await Future.delayed(const Duration(milliseconds: 100));
      await _linphonePlugin.toggleMute();
    } catch (e) {
      _log('Could not reset audio: $e');
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
      Permission.phone,
    ].request();
    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      _log('Microphone permission denied – calling will not work');
    }
  }

  Future<void> _register() async {
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
      _registrationError = '';
    });
    _log('Attempting SIP registration...');

    try {
      await _linphonePlugin.login(
        userName: username,
        domain: domain,
        password: password,
      );
      await Future.delayed(const Duration(seconds: 5));
      setState(() {
        _registrationState = RegistrationState.Ok;
        _isRegistered = true;
      });
      _log('Registration successful');
      setState(() => _selectedIndex = 0);
    } catch (e) {
      setState(() {
        _registrationState = RegistrationState.Failed;
        _isRegistered = false;
        _registrationError = e.toString();
      });
      _log('Registration failed: $e');
    }
  }

  Future<void> _logout() async {
    try {
      if (_currentCallState != null &&
          _currentCallState != CallState.Idle &&
          _currentCallState != CallState.End) {
        await _hangUp();
      }
      setState(() {
        _isRegistered = false;
        _registrationState = RegistrationState.None;
        _currentCallState = null;
      });
      _log('Logged out');
    } catch (e) {
      _log('Logout error: $e');
    }
  }

  Future<void> _makeCall() async {
    final number = _dialNumberController.text.trim();
    if (number.isEmpty) {
      _log('Please enter a number');
      return;
    }
    if (!_isRegistered) {
      _log('Not registered – cannot call');
      return;
    }
    _lastDialedNumber = number;
    _callStartTime = null; // will be set when Connected state arrives
    try {
      await _linphonePlugin.call(number: number);
      _log('Calling $number...');
    } catch (e) {
      _log('Failed to call: $e');
    }
  }

  Future<void> _hangUp() async {
    try {
      await _linphonePlugin.hangUp();
      _log('Call ended');
    } catch (e) {
      _log('Hang up error: $e');
    }
  }

  void _log(String msg) {
    setState(() => _debugMessage = msg);
    print(msg);
  }

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

  // ---------- Dialer UI ----------
  Widget _buildDialer() {
    return Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: _dialNumberController,
                  style: const TextStyle(fontSize: 28),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Enter number',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_currentCallState != null)
                Chip(
                  label: Text(
                    'Call: ${_currentCallState.toString().split('.').last}',
                  ),
                  backgroundColor: Colors.grey[200],
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _makeCall,
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  ElevatedButton.icon(
                    onPressed: _hangUp,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Hang Up'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 1; i <= 9; i++) _dialButton(i.toString()),
                  _dialButton('0'),
                  _dialButton('*'),
                  _dialButton('#'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dialButton(String digit) {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        onPressed: () => _dialNumberController.text += digit,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(digit, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  // ---------- Call Log UI (local) ----------
  Widget _buildCallLog() {
    if (_callLogs.isEmpty) {
      return const Center(child: Text('No call logs yet'));
    }
    return ListView.builder(
      itemCount: _callLogs.length,
      itemBuilder: (context, index) {
        final log = _callLogs[index];
        return ListTile(
          leading: Icon(
            log.status == 'Outgoing' ? Icons.call_made : Icons.call_received,
            color: log.status == 'Outgoing' ? Colors.green : Colors.blue,
          ),
          title: Text(log.number),
          subtitle: Text('${log.date.toLocal()}  ·  ${log.duration}s'),
          trailing: IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              _dialNumberController.text = log.number;
              setState(() => _selectedIndex = 0);
            },
          ),
        );
      },
    );
  }

  // ---------- Settings UI ----------
  Widget _buildSettings() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _sipUsernameController,
            decoration: const InputDecoration(labelText: 'SIP Username'),
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
          const SizedBox(height: 20),
          if (_registrationState == RegistrationState.Progress)
            const CircularProgressIndicator()
          else
            ElevatedButton(
              onPressed: _isRegistered ? _logout : _register,
              child: Text(_isRegistered ? 'Logout' : 'Register'),
            ),
          if (_registrationState == RegistrationState.Ok)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '✅ Registered',
                style: TextStyle(color: Colors.green),
              ),
            ),
          if (_registrationState == RegistrationState.Failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '❌ Registration failed: $_registrationError',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 30),
          const Divider(),
          const Text(
            'Debug Log',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_debugMessage),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number 6 Softphone'),
        actions: [
          if (_isRegistered)
            IconButton(
              icon: const Icon(Icons.call),
              onPressed: () => setState(() => _selectedIndex = 0),
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [_buildDialer(), _buildCallLog(), _buildSettings()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dialpad), label: 'Dialer'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Call Log'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
