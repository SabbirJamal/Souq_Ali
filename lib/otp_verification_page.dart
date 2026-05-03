import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'seller_home_page.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({
    super.key,
    required this.phoneNumber,
    required this.isRegistration,
    this.sellerName,
  });

  final String phoneNumber;
  final bool isRegistration;
  final String? sellerName;

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _otpController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _verificationId;
  String _statusMessage = 'Preparing OTP...';
  bool _isSendingOtp = true;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _verificationId = null;
      _isSendingOtp = true;
      _statusMessage = 'Sending OTP to ${widget.phoneNumber}...';
    });

    await _auth.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSendingOtp = false;
          _statusMessage = error.message ?? 'Could not send OTP.';
        });
        _showMessage(_statusMessage);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) {
          return;
        }
        setState(() {
          _verificationId = verificationId;
          _isSendingOtp = false;
          _statusMessage = 'OTP is ready. Enter the code to continue.';
        });
        _showMessage('OTP sent to ${widget.phoneNumber}');
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        if (!mounted) {
          return;
        }
        setState(() {
          _verificationId = verificationId;
          _isSendingOtp = false;
          _statusMessage =
              'Auto verification timed out. Enter the OTP manually.';
        });
      },
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    final verificationId = _verificationId;

    if (otp.length < 6) {
      _showMessage('Enter the 6 digit OTP');
      return;
    }
    if (verificationId == null) {
      _showMessage(_statusMessage);
      return;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    setState(() => _isVerifying = true);

    try {
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        _showMessage('Login failed. Please try again.');
        return;
      }

      if (widget.isRegistration) {
        await _saveSellerProfile(user);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SellerHomePage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Invalid OTP. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _saveSellerProfile(User user) {
    return _firestore.collection('sellers').doc(user.uid).set({
      'uid': user.uid,
      'name': widget.sellerName,
      'phoneNumber': widget.phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final isBusy = _isSendingOtp || _isVerifying;
    final canVerify = !isBusy && _verificationId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter OTP',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'A verification code was sent to ${widget.phoneNumber}.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    prefixIcon: Icon(Icons.lock),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: canVerify ? _verifyOtp : null,
                  icon: isBusy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified),
                  label: Text(
                    _isSendingOtp
                        ? 'Sending OTP...'
                        : _verificationId == null
                        ? 'Waiting for OTP'
                        : 'Verify OTP',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isBusy ? null : _sendOtp,
                  child: const Text('Resend OTP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
