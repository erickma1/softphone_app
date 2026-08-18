import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _subjectController =
      TextEditingController();

  final TextEditingController _messageController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSending = false;

  String _errorMessage = '';

  List<String> _categories = [];
  String? _selectedCategory;

  String _whatsappUsername = '';

  @override
  void initState() {
    super.initState();
    _loadSupportInfo();
  }

  Future<void> _loadSupportInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await AuthService.getSupportInfo();

    if (!mounted) return;

    if (result['success'] == true) {
      final rawCategories = result['categories'];

      final categories = <String>[];

      if (rawCategories is List) {
        for (final item in rawCategories) {
          final value = item?.toString().trim() ?? '';

          if (value.isNotEmpty) {
            categories.add(value);
          }
        }
      }

      setState(() {
        _categories = categories;
        _whatsappUsername =
            result['whatsappUsername']?.toString() ?? '';

        if (_categories.isNotEmpty) {
          _selectedCategory = _categories.first;
        }

        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['message']?.toString() ??
            'Could not load support information.';
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategory == null ||
        _selectedCategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a support category.',
          ),
        ),
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSending = true;
    });

    final result = await AuthService.sendSupportMessage(
      category: _selectedCategory!,
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSending = false;
    });

    if (result['success'] == true) {
      _subjectController.clear();
      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Support message sent successfully.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Could not send support message.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _copyWhatsAppUsername() async {
    if (_whatsappUsername.isEmpty) return;

    await Clipboard.setData(
      ClipboardData(
        text: _whatsappUsername,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '@$_whatsappUsername copied',
        ),
      ),
    );
  }

  Widget _buildSupportForm() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send us a message',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Tell us what you need help with.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),

              const SizedBox(height: 20),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: const Icon(
                    Icons.category_outlined,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: _isSending
                    ? null
                    : (value) {
                        setState(() {
                          _selectedCategory = value;
                        });
                      },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _subjectController,
                enabled: !_isSending,
                maxLength: 150,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Briefly describe the issue',
                  prefixIcon: const Icon(
                    Icons.subject,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) {
                    return 'Please enter a subject.';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 8),

              TextFormField(
                controller: _messageController,
                enabled: !_isSending,
                minLines: 6,
                maxLines: 10,
                maxLength: 5000,
                textCapitalization:
                    TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Message',
                  hintText:
                      'Describe the problem in detail...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';

                  if (text.isEmpty) {
                    return 'Please enter your message.';
                  }

                  if (text.length < 10) {
                    return 'Please provide more details.';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your account details such as your email, '
                        'phone number and SIP account are attached '
                        'automatically to help our support team '
                        'identify your account.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send_outlined,
                        ),
                  label: Text(
                    _isSending
                        ? 'Sending...'
                        : 'Send Message',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsAppSupport() {
    if (_whatsappUsername.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.green.shade100,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Colors.green.shade50,
                  child: const Icon(
                    Icons.chat_outlined,
                    color: Colors.green,
                  ),
                ),

                const SizedBox(width: 12),

                const Expanded(
                  child: Text(
                    'WhatsApp Support',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Text(
              '@$_whatsappUsername',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Search this exact username in WhatsApp '
              'to contact Number 6 support.',
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _copyWhatsAppUsername,
                icon: const Icon(
                  Icons.copy,
                ),
                label: const Text(
                  'Copy WhatsApp Username',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
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
        title: const Text('Support'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.support_agent,
                          size: 52,
                          color: Colors.grey,
                        ),

                        const SizedBox(height: 14),

                        Text(
                          _errorMessage,
                          textAlign:
                              TextAlign.center,
                        ),

                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          onPressed:
                              _loadSupportInfo,
                          icon: const Icon(
                            Icons.refresh,
                          ),
                          label: const Text(
                            'Try Again',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSupportInfo,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'How can we help?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Send a support request or contact us through WhatsApp.',
                        style: TextStyle(
                          color:
                              Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 22),

                      _buildSupportForm(),

                      const SizedBox(height: 20),

                      _buildWhatsAppSupport(),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}