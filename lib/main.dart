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
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const SoftphoneHomePage(),
    );
  }
}

class CallLogEntry {
  final String number;
  final String status;
  final DateTime date;
  final int duration;
  final bool answered;

  CallLogEntry({
    required this.number,
    required this.status,
    required this.date,
    required this.duration,
    required this.answered,
  });

  String getDurationString() {
    if (!answered || duration == 0) return '';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    if (minutes == 0) return '${seconds}s';
    if (seconds == 0) return '${minutes}m';
    return '${minutes}m ${seconds}s';
  }
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
  int _selectedIndex = 0;

  final _sipUsernameController = TextEditingController();
  final _sipPasswordController = TextEditingController();
  final _sipDomainController = TextEditingController();
  final _dialNumberController = TextEditingController();

  bool _isRegistered = false;
  RegistrationState _registrationState = RegistrationState.None;
  String _registrationError = '';
  CallState? _currentCallState;
  String _debugMessage = '';

  DateTime? _callStartTime;
  int _callDuration = 0;
  String? _currentCallNumber;
  List<CallLogEntry> _callLogs = [];
  bool _isOutgoingCall = false;

  @override
  void initState() {
    super.initState();
    _initAndSetup();
    _dialNumberController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initAndSetup() async {
    await _requestPermissions();

    _linphonePlugin.addCallStateListener().listen((dynamic state) {
      final callState = _convertCallState(state);
      setState(() => _currentCallState = callState);
      _log('Call state changed: $callState');

      if (callState == CallState.Connected && _callStartTime == null) {
        _callStartTime = DateTime.now();
        _log('Call connected');
      }

      if (callState == CallState.IncomingReceived) {
        _isOutgoingCall = false;
        _currentCallNumber = 'Incoming call';
        _showIncomingCallDialog();
      }

      if (callState == CallState.End || callState == CallState.Error) {
        _handleCallEnd();
      }
    });

    _linphonePlugin.addLoginListener().listen((dynamic state) {
      _log('Registration state: $state');
      if (state.toString().toLowerCase().contains('ok')) {
        setState(() {
          _registrationState = RegistrationState.Ok;
          _isRegistered = true;
          _debugMessage = 'Registration confirmed';
        });
      } else if (state.toString().toLowerCase().contains('progress')) {
        setState(() {
          _registrationState = RegistrationState.Progress;
        });
      } else if (state.toString().toLowerCase().contains('failed')) {
        setState(() {
          _registrationState = RegistrationState.Failed;
          _isRegistered = false;
          _debugMessage = 'Registration failed';
        });
      }
    });
  }

  void _handleCallEnd() {
    String numberToLog =
        _currentCallNumber ?? _dialNumberController.text.trim();
    if (numberToLog.isEmpty || numberToLog == 'Incoming call')
      numberToLog = 'Unknown';

    if (_callStartTime != null && _currentCallState == CallState.Connected) {
      _callDuration = DateTime.now().difference(_callStartTime!).inSeconds;
      if (_callDuration > 1) {
        _addCallLog(
          numberToLog,
          _isOutgoingCall ? 'Outgoing' : 'Incoming',
          _callDuration,
          true,
        );
      } else {
        _addCallLog(
          numberToLog,
          _isOutgoingCall ? 'Outgoing' : 'Missed',
          0,
          false,
        );
      }
    } else {
      _addCallLog(
        numberToLog,
        _isOutgoingCall ? 'Outgoing' : 'Missed',
        0,
        false,
      );
    }

    _callStartTime = null;
    _callDuration = 0;
    _currentCallNumber = null;
  }

  void _addCallLog(String number, String status, int duration, bool answered) {
    if (number.isEmpty) return;
    setState(() {
      _callLogs.insert(
        0,
        CallLogEntry(
          number: number,
          status: status,
          date: DateTime.now(),
          duration: duration,
          answered: answered,
        ),
      );
      if (_callLogs.length > 100) _callLogs.removeLast();
    });
  }

  void _showIncomingCallDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: const Text('You have an incoming call.'),
        actions: [
          TextButton(
            onPressed: () async {
              _isOutgoingCall = false;
              await _rejectCall();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Reject'),
          ),
          TextButton(
            onPressed: () async {
              _isOutgoingCall = false;
              await _answerCall();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Answer'),
          ),
        ],
      ),
    );
  }

  Future<void> _answerCall() async {
    try {
      await _linphonePlugin.answerCall();
      _log('Call answered');
    } catch (e) {
      _log('Failed to answer call: $e');
    }
  }

  Future<void> _rejectCall() async {
    try {
      await _linphonePlugin.rejectCall();
      _log('Call rejected');
    } catch (e) {
      _log('Failed to reject call: $e');
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
      Permission.phone,
    ].request();
    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      _log('Microphone permission denied');
    }
  }

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
      _debugMessage = 'Attempting SIP registration...';
    });

    try {
      await _linphonePlugin.login(
        userName: username,
        domain: domain,
        password: password,
      );
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _registrationState == RegistrationState.Progress) {
          setState(() {
            _registrationState = RegistrationState.Failed;
            _isRegistered = false;
            _debugMessage = 'Registration timeout';
          });
        }
      });
    } catch (e) {
      setState(() {
        _registrationState = RegistrationState.Failed;
        _isRegistered = false;
        _debugMessage = 'Registration error: ${e.toString()}';
      });
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
      _log('Not registered');
      return;
    }
    try {
      _isOutgoingCall = true;
      _currentCallNumber = number;
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
    print('[Softphone] $msg');
  }

  CallState _convertCallState(dynamic state) {
    final s = state.toString().toLowerCase();
    if (s.contains('incoming')) return CallState.IncomingReceived;
    if (s.contains('dialing') || s.contains('outgoinginit'))
      return CallState.Dialing;
    if (s.contains('ringing')) return CallState.Ringing;
    if (s.contains('connected')) return CallState.Connected;
    if (s.contains('streams')) return CallState.StreamsRunning;
    if (s.contains('end') || s.contains('released')) return CallState.End;
    if (s.contains('error')) return CallState.Error;
    return CallState.Idle;
  }

  // UI Components
  Widget _buildDialer() {
    bool isCallActive =
        _currentCallState != null &&
        _currentCallState != CallState.Idle &&
        _currentCallState != CallState.End &&
        _currentCallState != CallState.Error;
    bool hasText = _dialNumberController.text.isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _dialNumberController,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (_currentCallState != null &&
                          _currentCallState != CallState.Idle)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Chip(
                            label: Text(
                              _currentCallState.toString().split('.').last,
                            ),
                            backgroundColor: _getCallStateColor(),
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _circularDialButton('1', ''),
                          _circularDialButton('2', 'ABC'),
                          _circularDialButton('3', 'DEF'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _circularDialButton('4', 'GHI'),
                          _circularDialButton('5', 'JKL'),
                          _circularDialButton('6', 'MNO'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _circularDialButton('7', 'PQRS'),
                          _circularDialButton('8', 'TUV'),
                          _circularDialButton('9', 'WXYZ'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _circularDialButton('*', ''),
                          _circularDialButton('0', '+'),
                          _circularDialButton('#', ''),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                // Action buttons: Speaker (left), Call (center), Backspace (right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton.extended(
                      onPressed: () {
                        _linphonePlugin.toggleSpeaker();
                        _log('Speaker toggled');
                      },
                      icon: const Icon(Icons.volume_up),
                      backgroundColor: Colors.blue[400],
                      label: const SizedBox.shrink(),
                    ),
                    FloatingActionButton(
                      onPressed: isCallActive ? _hangUp : _makeCall,
                      backgroundColor: isCallActive ? Colors.red : Colors.green,
                      child: Icon(
                        isCallActive ? Icons.call_end : Icons.call,
                        size: 32,
                      ),
                    ),
                    if (hasText)
                      FloatingActionButton.extended(
                        onPressed: () {
                          final text = _dialNumberController.text;
                          if (text.isNotEmpty) {
                            _dialNumberController.text = text.substring(
                              0,
                              text.length - 1,
                            );
                          }
                        },
                        icon: const Icon(Icons.backspace),
                        backgroundColor: Colors.grey[400],
                        label: const SizedBox.shrink(),
                      )
                    else
                      const SizedBox(width: 56),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circularDialButton(String digit, String letters) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _dialNumberController.text += digit,
          customBorder: const CircleBorder(),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[300]!, width: 2),
              color: Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCallStateColor() {
    switch (_currentCallState) {
      case CallState.Dialing:
      case CallState.Ringing:
        return Colors.orange;
      case CallState.Connected:
      case CallState.StreamsRunning:
        return Colors.green;
      case CallState.IncomingReceived:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildCallLog() {
    if (_callLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_missed, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No call logs yet', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _callLogs.length,
      itemBuilder: (context, index) {
        final log = _callLogs[index];
        final durationStr = log.getDurationString();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getCallLogIconColor(log.status).withOpacity(0.2),
              ),
              child: Icon(
                _getCallLogIcon(log.status),
                color: _getCallLogIconColor(log.status),
              ),
            ),
            title: Text(
              log.number,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${log.status} • ${_formatDateTime(log.date)}${durationStr.isNotEmpty ? ' • $durationStr' : ''}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () {
                _dialNumberController.text = log.number;
                setState(() => _selectedIndex = 0);
              },
            ),
          ),
        );
      },
    );
  }

  IconData _getCallLogIcon(String status) {
    switch (status) {
      case 'Outgoing':
        return Icons.call_made;
      case 'Incoming':
        return Icons.call_received;
      case 'Missed':
        return Icons.call_missed;
      default:
        return Icons.call;
    }
  }

  Color _getCallLogIconColor(String status) {
    switch (status) {
      case 'Outgoing':
        return Colors.green;
      case 'Incoming':
        return Colors.blue;
      case 'Missed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dtDate = DateTime(dt.year, dt.month, dt.day);
    if (dtDate == today)
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dtDate == yesterday)
      return 'Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SIP Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sipUsernameController,
              decoration: InputDecoration(
                labelText: 'SIP Username',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sipPasswordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sipDomainController,
              decoration: InputDecoration(
                labelText: 'Domain (e.g., sip.example.com)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.domain),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _registrationState == RegistrationState.Progress
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _isRegistered ? _logout : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: _isRegistered
                            ? Colors.red
                            : Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _isRegistered ? 'Logout' : 'Register',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            if (_registrationState == RegistrationState.Ok)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Successfully registered',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_registrationState == RegistrationState.Failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Registration failed: $_registrationError',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 32),
            const Divider(),
            const Text(
              'Debug Log',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _debugMessage.isEmpty ? 'No messages' : _debugMessage,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        elevation: 0,
        actions: [
          if (_isRegistered)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
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

  @override
  void dispose() {
    _sipUsernameController.dispose();
    _sipPasswordController.dispose();
    _sipDomainController.dispose();
    _dialNumberController.dispose();
    super.dispose();
  }
}
