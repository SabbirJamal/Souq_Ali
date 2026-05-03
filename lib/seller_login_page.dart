import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_register_page.dart';
import 'seller_session.dart';

class SellerLoginPage extends StatefulWidget {
  const SellerLoginPage({super.key});

  @override
  State<SellerLoginPage> createState() => _SellerLoginPageState();
}

class _SellerLoginPageState extends State<SellerLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phoneNumber = _omanPhoneNumber(_phoneController.text);

    setState(() => _isLoggingIn = true);

    try {
      final sellerDoc = await FirebaseFirestore.instance
          .collection('sellers')
          .doc(phoneNumber)
          .get();

      final seller = sellerDoc.data();
      if (!sellerDoc.exists || seller == null) {
        _showMessage('Seller account not found. Please register first.');
        return;
      }

      await SellerSession.save(
        sellerId: phoneNumber,
        name: seller['name']?.toString() ?? 'Seller',
        phoneNumber: phoneNumber,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SellerHomePage()),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      _showMessage('Error: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Error: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seller Login')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your registered phone number to continue.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '90000000',
                      prefixText: '+968 ',
                      prefixIcon: Icon(Icons.phone),
                      counterText: '',
                    ),
                    validator: _validatePhoneNumber,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isLoggingIn ? null : _login,
                    icon: _isLoggingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isLoggingIn ? 'Logging in...' : 'Login'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SellerRegisterPage(),
                        ),
                      );
                    },
                    child: const Text('New seller? Register'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _validatePhoneNumber(String? value) {
  final phone = _localDigits(value);
  if (phone.isEmpty) {
    return 'Enter your phone number';
  }
  if (phone.length != 8) {
    return 'Enter the 8 digit Oman phone number';
  }
  return null;
}

String _omanPhoneNumber(String value) {
  return '+968${_localDigits(value)}';
}

String _localDigits(String? value) {
  return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
}
