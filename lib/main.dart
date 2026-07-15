import 'package:flutter/material.dart';
import 'package:linphone_flutter_plugin/linphoneflutterplugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

// Import your actual auth screens and service (these exist in separate files)
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MySoftphoneApp());
}

class MySoftphoneApp extends StatelessWidget {
  const MySoftphoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Number 6 Softphone',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const SplashScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const SoftphoneHomePage(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final auth = AuthService();
    final token = await auth.getToken();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      if (token != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, size: 64, color: Colors.blue[600]),
            const SizedBox(height: 16),
            const Text('Number 6 Softphone'),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// --------------------- Softphone Models & Enums ---------------------
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

// --------------------- Main Softphone Home Page ---------------------
class SoftphoneHomePage extends StatefulWidget {
  const SoftphoneHomePage({super.key});

  @override
  State<SoftphoneHomePage> createState() => _SoftphoneHomePageState();
}

class _SoftphoneHomePageState extends State<SoftphoneHomePage> {
  final LinphoneFlutterPlugin _linphonePlugin = LinphoneFlutterPlugin();
  // int _selectedIndex = 0; // 0: Dialer, 1: Contacts, 2: Call Log, 3: Settings
  int _selectedIndex = 0;

  // SIP settings
  final _sipUsernameController = TextEditingController();
  final _sipPasswordController = TextEditingController();
  final _sipDomainController = TextEditingController();
  final _dialNumberController = TextEditingController();

  bool _isRegistered = false;
  RegistrationState _registrationState = RegistrationState.None;
  String _registrationError = '';
  CallState? _currentCallState;
  String _debugMessage = '';

  // Call tracking
  DateTime? _callStartTime;
  int _callDuration = 0;
  String? _currentCallNumber;
  List<CallLogEntry> _callLogs = [];
  bool _isOutgoingCall = false;

  // Contacts
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  final TextEditingController _searchController = TextEditingController();
  Future<List<Contact>>? _contactsFuture;

  // Wallet and server CDRs
  Map<String, dynamic>? _walletBalance;
  List<dynamic> _topups = [];
  List<dynamic> _serverCdrs = [];

  bool _walletLoading = false;
  bool _historyLoading = false;

  String? _walletError;
  String? _historyError;

  Future<void> _loadSavedSipDetails() async {
    final auth = AuthService();
    final sip = await auth.getSipDetails();

    final username = sip['username'];
    final password = sip['password'];
    final domain = sip['domain'];

    if (username != null && password != null && domain != null) {
      setState(() {
        _sipUsernameController.text = username;
        _sipPasswordController.text = password;
        _sipDomainController.text = domain;
        _debugMessage = 'SIP details loaded';
      });

      await _login();
    }
  }

  @override
  void initState() {
    super.initState();
    _initAndSetup();
    _loadSavedSipDetails();
    _loadWalletData();
    _loadServerCdrs();
    _dialNumberController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(_filterContacts);
    _contactsFuture = _autoLoadContacts();
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

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _loadWalletData();
        _loadServerCdrs();
      }
    });
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

  // ---------- Contacts methods ----------
  void _filterContacts() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredContacts = List.from(_contacts);
      } else {
        _filteredContacts = _contacts.where((contact) {
          final name = contact.displayName.toLowerCase();
          final phones = contact.phones
              .map((p) => p.number)
              .join(' ')
              .toLowerCase();
          return name.contains(query) || phones.contains(query);
        }).toList();
      }
    });
  }

  Future<List<Contact>> _autoLoadContacts() async {
    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      final granted = await Permission.contacts.request();
      if (!granted.isGranted) {
        throw Exception('Contacts permission denied');
      }
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    return contacts;
  }

  Future<void> _loadWalletData() async {
    if (!mounted) return;

    setState(() {
      _walletLoading = true;
      _walletError = null;
    });

    try {
      final balanceResult = await AuthService.getBalance();
      final topupsResult = await AuthService.getTopups();

      if (!mounted) return;

      setState(() {
        if (balanceResult['success'] == true) {
          _walletBalance = Map<String, dynamic>.from(balanceResult['balance']);
        } else {
          _walletError = balanceResult['message'] ?? 'Could not load balance';
        }

        if (topupsResult['success'] == true) {
          _topups = List<dynamic>.from(topupsResult['topups']);
        }

        _walletLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _walletLoading = false;
        _walletError = e.toString();
      });
    }
  }

  Future<void> _loadServerCdrs() async {
    if (!mounted) return;

    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final result = await AuthService.getCdrs();

      if (!mounted) return;

      setState(() {
        if (result['success'] == true) {
          _serverCdrs = List<dynamic>.from(result['cdrs']);
        } else {
          _historyError = result['message'] ?? 'Could not load call history';
        }

        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _historyLoading = false;
        _historyError = e.toString();
      });
    }
  }

  String _formatDurationFromSeconds(dynamic value) {
    final seconds = int.tryParse(value?.toString() ?? '0') ?? 0;

    if (seconds <= 0) return '0s';

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (minutes == 0) return '${remainingSeconds}s';
    if (remainingSeconds == 0) return '${minutes}m';

    return '${minutes}m ${remainingSeconds}s';
  }

  String _formatServerDate(dynamic value) {
    if (value == null) return '';

    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();

    return _formatDateTime(parsed.toLocal());
  }

  String _moneyText(dynamic amount, dynamic currency) {
    final a = amount?.toString() ?? '0';
    final c = currency?.toString().toUpperCase() ?? 'USD';

    return '$c $a';
  }

  void _showTopUpDialog() {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Top Up Wallet'),
          content: TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              hintText: 'Example: 10',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = amountController.text.trim();

                if (amount.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext);

                final result = await AuthService.createCheckoutSession(
                  amount: amount,
                );

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Top-up request sent'),
                    backgroundColor: result['success'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                );

                await _loadWalletData();
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWallet() {
    final amount = _walletBalance?['amount']?.toString() ?? '0';
    final currency =
        _walletBalance?['currency']?.toString().toUpperCase() ?? 'USD';

    return RefreshIndicator(
      onRefresh: _loadWalletData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[700],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '$currency $amount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showTopUpDialog,
                    icon: const Icon(Icons.add_card),
                    label: const Text('Top Up'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_walletLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),

          if (_walletError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                _walletError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top-up History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _loadWalletData,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          if (_topups.isEmpty && !_walletLoading)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Text(
                'No top-ups yet',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else
            ..._topups.map((item) {
              final topup = Map<String, dynamic>.from(item);
              final topupAmount = topup['amount'];
              final topupCurrency = topup['currency'];
              final status = topup['status']?.toString() ?? '';
              final provider = topup['provider']?.toString() ?? '';
              final createdAt = _formatServerDate(topup['created_at']);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: status == 'success'
                        ? Colors.green[100]
                        : Colors.orange[100],
                    child: Icon(
                      status == 'success' ? Icons.check : Icons.pending,
                      color: status == 'success' ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(
                    _moneyText(topupAmount, topupCurrency),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$provider • $status • $createdAt'),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildServerHistory() {
    return RefreshIndicator(
      onRefresh: _loadServerCdrs,
      child: _historyLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyError != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    _historyError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadServerCdrs,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            )
          : _serverCdrs.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.history, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'No server call history yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _loadServerCdrs,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _serverCdrs.length,
              itemBuilder: (context, index) {
                final call = Map<String, dynamic>.from(_serverCdrs[index]);

                final number =
                    call['dialed_number']?.toString().isNotEmpty == true
                    ? call['dialed_number'].toString()
                    : call['callee']?.toString() ?? 'Unknown';

                final duration = _formatDurationFromSeconds(
                  call['connected_seconds'],
                );

                final answeredTime = _formatServerDate(call['answered_time']);

                final cost =
                    call['cost'] ?? call['charged_amount'] ?? call['amount'];

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green[100],
                      child: const Icon(Icons.call_made, color: Colors.green),
                    ),
                    title: Text(
                      number,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      cost != null
                          ? '$answeredTime • $duration • Cost: $cost'
                          : '$answeredTime • $duration',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () {
                        _dialNumberController.text = number;
                        setState(() => _selectedIndex = 0);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ---------- UI Components ----------
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

  // ---------- Contacts Tab ----------
  Widget _buildContacts() {
    if (_contactsFuture == null) {
      return const Center(child: Text('Error loading contacts'));
    }
    return FutureBuilder<List<Contact>>(
      future: _contactsFuture!,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _contactsFuture = _autoLoadContacts();
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final contacts = snapshot.data ?? [];
        if (_contacts != contacts) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _contacts = contacts;
              _filteredContacts = contacts;
            });
          });
        }
        return _buildContactListWithSearch();
      },
    );
  }

  Widget _buildContactListWithSearch() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or number',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterContacts();
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _contacts.isEmpty
              ? const Center(child: Text('No contacts found'))
              : (_filteredContacts.isEmpty && _searchController.text.isNotEmpty)
              ? Center(
                  child: Text('No contacts match "${_searchController.text}"'),
                )
              : ListView.builder(
                  itemCount: _filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = _filteredContacts[index];
                    final hasNumber = contact.phones.isNotEmpty;
                    final phoneNumber = hasNumber
                        ? contact.phones.first.number
                        : '';
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          contact.displayName.isNotEmpty
                              ? contact.displayName[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(contact.displayName),
                      subtitle: hasNumber
                          ? Text(phoneNumber)
                          : const Text('No number'),
                      trailing: hasNumber
                          ? IconButton(
                              icon: const Icon(Icons.call, color: Colors.green),
                              onPressed: () {
                                _dialNumberController.text = phoneNumber;
                                setState(() => _selectedIndex = 0);
                              },
                            )
                          : null,
                      onTap: hasNumber
                          ? () {
                              _dialNumberController.text = phoneNumber;
                              setState(() => _selectedIndex = 0);
                            }
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------- Call Log Tab ----------
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

  // ---------- Settings Tab ----------
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
                        _isRegistered ? 'Logout SIP' : 'Register SIP',
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
              'App Account',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final auth = AuthService();
                  await auth.clearToken();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Logout from App',
                  style: TextStyle(color: Colors.white),
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
        children: [
          _buildDialer(),
          _buildContacts(),
          _buildWallet(),
          _buildServerHistory(),
          _buildSettings(),
        ],
      ),
      // body: IndexedStack(
      //   index: _selectedIndex,
      //   children: [
      //     _buildDialer(),
      //     _buildContacts(),
      //     _buildCallLog(),
      //     _buildSettings(),
      //   ],
      // ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        // items: const [
        //   BottomNavigationBarItem(icon: Icon(Icons.dialpad), label: 'Dialer'),
        //   BottomNavigationBarItem(
        //     icon: Icon(Icons.contacts),
        //     label: 'Contacts',
        //   ),
        //   BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Call Log'),
        //   BottomNavigationBarItem(
        //     icon: Icon(Icons.settings),
        //     label: 'Settings',
        //   ),
        // ],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dialpad), label: 'Dialer'),
          BottomNavigationBarItem(
            icon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
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
    _searchController.dispose();
    super.dispose();
  }
}
