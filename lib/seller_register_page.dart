import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';

class SellerRegisterPage extends StatefulWidget {
  const SellerRegisterPage({super.key});

  @override
  State<SellerRegisterPage> createState() => _SellerRegisterPageState();
}

class _SellerRegisterPageState extends State<SellerRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isRegistering = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final phoneNumber = _omanPhoneNumber(_phoneController.text);

    setState(() => _isRegistering = true);

    try {
      final sellerRef = FirebaseFirestore.instance
          .collection('sellers')
          .doc(phoneNumber);
      final existingSeller = await sellerRef.get();
      if (existingSeller.exists) {
        _showMessage('This phone number is already registered.');
        return;
      }

      await sellerRef.set({
            'uid': phoneNumber,
            'name': name,
            'phoneNumber': phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await SellerSession.save(
        sellerId: phoneNumber,
        name: name,
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
        setState(() => _isRegistering = false);
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
      appBar: AppBar(
        title: const SizedBox(
          height: kToolbarHeight,
          width: 145,
          child: Image(
            image: AssetImage('assets/branding/logo.png'),
            fit: BoxFit.cover,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4FBF7),
        foregroundColor: Colors.black,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        onTap: (_) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const SellerHomePage(isSellerMode: false),
            ),
            (route) => false,
          );
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF7801),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        iconSize: 24,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_fill),
            label: 'Stories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Add',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Listings'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
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
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Company name',
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) {
                        return 'Enter company name';
                      }
                      if (name.length < 2) {
                        return 'Company name is too short';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
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
                    onPressed: _isRegistering ? null : _register,
                    icon: _isRegistering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                      )
                        : const Icon(Icons.app_registration),
                    label: Text(
                      _isRegistering ? 'Creating...' : 'Create Account',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7801),
                      foregroundColor: Colors.white,
                    ),
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
