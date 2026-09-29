import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class RegistrationScreen extends StatefulWidget {
  final String plan;

  const RegistrationScreen({super.key, this.plan = 'monthly'});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _selectedPaymentMethod = 'mobile_money';
  bool _isSubmitting = false;

  static const String _paymentBackendUrl = String.fromEnvironment(
    'PAYMENT_BACKEND_URL',
    defaultValue: 'http://localhost:3000/api/payments/initialize',
  );
  static final Uri _monthlyCheckoutUri = Uri.parse(
    'https://paystack.shop/pay/6xyhc-jiyn',
  );
  static final Uri _yearlyCheckoutUri = Uri.parse(
    'https://paystack.shop/pay/p7qv5q3xh5',
  );

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    if ((widget.plan == 'monthly' || widget.plan == 'yearly') &&
        (_selectedPaymentMethod == 'mobile_money' ||
            _selectedPaymentMethod == 'bank_card')) {
      final checkoutUri = widget.plan == 'yearly'
          ? _yearlyCheckoutUri
          : _monthlyCheckoutUri;
      final launched = await launchUrl(
        checkoutUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the payment page.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final email = _emailController.text.trim();
    final fullName = _fullNameController.text.trim();

    try {
      final response = await http.post(
        Uri.parse(_paymentBackendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fullName': fullName,
          'phone': _phoneController.text.trim(),
          'email': email.isEmpty ? null : email,
          'plan': widget.plan,
          'paymentMethod': _selectedPaymentMethod,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Payment initialization failed');
      }

      final payment = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        payment['message'] ?? 'USSD payment provider is not configured yet.',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to the payment service.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),
                        Image.asset(
                          'assets/images/watermark2.png',
                          width: 110,
                          height: 110,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Upgrade to Premium',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Complete your payment details to unlock premium features.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                        const SizedBox(height: 24),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildInputField(
                                controller: _fullNameController,
                                label: 'Full name',
                                hintText: 'Enter your full name',
                                keyboardType: TextInputType.name,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Full name is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              _buildInputField(
                                controller: _phoneController,
                                label: 'Phone number',
                                hintText: 'Enter your phone number',
                                keyboardType: TextInputType.phone,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Phone number is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              _buildInputField(
                                controller: _emailController,
                                label: 'Email (optional)',
                                hintText: 'Enter your email address',
                                keyboardType: TextInputType.emailAddress,
                                required: false,
                                validator: (value) {
                                  final trimmedValue = value?.trim() ?? '';
                                  if (trimmedValue.isEmpty) return null;
                                  return RegExp(
                                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                      ).hasMatch(trimmedValue)
                                      ? null
                                      : 'Enter a valid email address';
                                },
                              ),
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Payment method',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildPaymentOption(
                                      title: 'Mobile Money',
                                      selected:
                                          _selectedPaymentMethod ==
                                          'mobile_money',
                                      onTap: () => setState(() {
                                        _selectedPaymentMethod = 'mobile_money';
                                      }),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildPaymentOption(
                                      title: 'Bank Card',
                                      selected:
                                          _selectedPaymentMethod == 'bank_card',
                                      onTap: () => setState(() {
                                        _selectedPaymentMethod = 'bank_card';
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: 200,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Confirm Details',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.orange : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.orange : Colors.grey,
                  width: 2,
                ),
                color: selected ? Colors.orange : Colors.white,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required TextInputType keyboardType,
    String? Function(String?)? validator,
    bool required = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
