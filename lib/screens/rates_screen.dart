import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class RatesScreen extends StatefulWidget {
  const RatesScreen({super.key});

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _errorMessage = '';

  List<Map<String, dynamic>> _countries = [];
  Map<String, dynamic>? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    final result = await AuthService.getRates();

    if (!mounted) return;

    if (result['success'] == true) {
      final rawCountries = result['countries'];

      final countries = <Map<String, dynamic>>[];

      if (rawCountries is List) {
        for (final item in rawCountries) {
          if (item is Map) {
            countries.add(Map<String, dynamic>.from(item));
          }
        }
      }

      countries.sort((a, b) {
        final countryA = a['country']?.toString().toLowerCase() ?? '';
        final countryB = b['country']?.toString().toLowerCase() ?? '';

        return countryA.compareTo(countryB);
      });

      setState(() {
        _countries = countries;
        _isLoading = false;

        if (_selectedCountry != null) {
          final selectedName = _selectedCountry!['country']?.toString();

          _selectedCountry = countries.cast<Map<String, dynamic>?>().firstWhere(
            (country) => country?['country']?.toString() == selectedName,
            orElse: () => null,
          );
        }
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['message']?.toString() ?? 'Could not load call rates.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCountries {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return [];
    }

    return _countries.where((country) {
      final name = country['country']?.toString().toLowerCase() ?? '';

      return name.contains(query);
    }).toList();
  }

  void _selectCountry(Map<String, dynamic> country) {
    final name = country['country']?.toString() ?? '';

    setState(() {
      _selectedCountry = country;
      _searchController.text = name;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: name.length),
      );
    });

    FocusScope.of(context).unfocus();
  }

  void _onSearchChanged(String value) {
    final selectedName =
        _selectedCountry?['country']?.toString().toLowerCase() ?? '';

    if (value.trim().toLowerCase() != selectedName) {
      setState(() {
        _selectedCountry = null;
      });
    } else {
      setState(() {});
    }
  }

  String _billingDescription(Map<String, dynamic> rate) {
    final increment =
        int.tryParse(rate['billing_increment']?.toString() ?? '') ?? 0;

    final minimum =
        int.tryParse(rate['minimum_duration']?.toString() ?? '') ?? 0;

    if (increment == 1 && minimum <= 1) {
      return 'Billed per second';
    }

    if (increment == 1) {
      return 'Billed per second • Minimum $minimum seconds';
    }

    if (increment > 1) {
      return 'Billed in $increment-second increments';
    }

    return 'Charged based on connected call time';
  }

  List<Map<String, dynamic>> _countryRates(Map<String, dynamic> country) {
    final rawRates = country['rates'];

    if (rawRates is! List) {
      return [];
    }

    return rawRates
        .whereType<Map>()
        .map((rate) => Map<String, dynamic>.from(rate))
        .toList();
  }

  Widget _buildSearchResults() {
    final results = _filteredCountries;

    if (_searchController.text.trim().isEmpty || _selectedCountry != null) {
      return const SizedBox.shrink();
    }

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'No destination found.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: results.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final country = results[index];
          final countryName = country['country']?.toString() ?? 'Unknown';

          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.public, size: 20)),
            title: Text(countryName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectCountry(country),
          );
        },
      ),
    );
  }

  Widget _buildSelectedCountry() {
    final country = _selectedCountry;

    if (country == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.public, size: 42, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Select a destination',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Search for a country above to view its calling rate.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final countryName = country['country']?.toString() ?? 'Destination';

    final rates = _countryRates(country);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: const Icon(Icons.public, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  countryName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (rates.isEmpty)
            const Text('No active rate is available for this destination.'),

          ...rates.asMap().entries.map((entry) {
            final index = entry.key;
            final rate = entry.value;

            final displayRate =
                rate['display_rate']?.toString() ?? 'Rate unavailable';

            final prefix = rate['prefix']?.toString() ?? '';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rates.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      prefix.isEmpty ? 'Route ${index + 1}' : 'Prefix +$prefix',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                Text(
                  displayRate,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _billingDescription(rate),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),

                if (index < rates.length - 1) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Rates'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadRates,
            tooltip: 'Refresh rates',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(_errorMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadRates,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRates,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'International Call Rates',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Search for a destination to view your current calling rate.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search destination',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _selectedCountry = null;
                                });
                              },
                              icon: const Icon(Icons.close),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  _buildSearchResults(),

                  _buildSelectedCountry(),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The rate is selected automatically from the number you dial. '
                            'You do not need to select a country before making a call. '
                            'Charges are deducted from your prepaid wallet based on connected call time.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
