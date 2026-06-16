import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../seller_session.dart';
import '../utils/network_status.dart';
import '../widgets/app_toast.dart';

class SellerSettingsTab extends StatefulWidget {
  const SellerSettingsTab({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<SellerSettingsTab> createState() => _SellerSettingsTabState();
}

class _SellerSettingsTabState extends State<SellerSettingsTab> {
  late final Future<SellerSession?> _sessionFuture;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _sellerStream;

  @override
  void initState() {
    super.initState();
    _sessionFuture = SellerSession.current();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: _sessionFuture,
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data;
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (session == null) {
          return const Center(child: Text('Please login again'));
        }

        _sellerStream ??= FirebaseFirestore.instance
            .collection('sellers')
            .doc(session.sellerId)
            .snapshots();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _sellerStream,
          builder: (context, sellerSnapshot) {
            final seller = sellerSnapshot.data?.data() ?? {};
            final sellerName = seller['name']?.toString() ?? session.name;
            final crNumber =
                seller['cr_number']?.toString().trim().isNotEmpty == true
                ? seller['cr_number'].toString()
                : seller['crNumber']?.toString() ?? '';
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _formatSettingsPhone(session.phoneNumber),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SellerInfoField(
                    sellerId: session.sellerId,
                    fieldKey: 'name',
                    label: 'Company Name',
                    hint: 'Company Name',
                    initialValue: sellerName,
                    keyboardType: TextInputType.text,
                    inputFormatters: const [],
                    savedMessage: 'Company name saved',
                  ),
                  const SizedBox(height: 12),
                  _CrNumberField(
                    sellerId: session.sellerId,
                    initialValue: crNumber,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _formatSettingsPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('968') && digits.length > 3) {
    return '+968 ${digits.substring(3)}';
  }
  if (digits.isNotEmpty) {
    return '+968 $digits';
  }
  return value;
}

class _CrNumberField extends StatefulWidget {
  const _CrNumberField({required this.sellerId, required this.initialValue});

  final String sellerId;
  final String initialValue;

  @override
  State<_CrNumberField> createState() => _CrNumberFieldState();
}

class _CrNumberFieldState extends State<_CrNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CrNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _saveCrNumber() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.sellerId)
          .set({
            'cr_number': _controller.text.trim(),
            'crNumber': _controller.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() => _isEditing = false);
      AppToast.show(context, 'CR number saved');
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Error: ${error.message ?? error.code}',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      final value = _controller.text.trim();
      return _SettingsDisplayField(
        label: 'CR No.',
        value: value,
        isEmpty: value.isEmpty,
        onEdit: () => setState(() => _isEditing = true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsEditHeader(
          label: 'CR No.',
          onCancel: () {
            _controller.text = widget.initialValue;
            FocusScope.of(context).unfocus();
            setState(() => _isEditing = false);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !_isSaving,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'CR No.',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            height: 44,
            width: 104,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveCrNumber,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7801),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                )
                : const Text('Save'),
          ),
        ),
        ),
      ],
    );
  }
}

class _SellerInfoField extends StatefulWidget {
  const _SellerInfoField({
    required this.sellerId,
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.keyboardType,
    required this.inputFormatters,
    required this.savedMessage,
  });

  final String sellerId;
  final String fieldKey;
  final String label;
  final String hint;
  final String initialValue;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String savedMessage;

  @override
  State<_SellerInfoField> createState() => _SellerInfoFieldState();
}

class _SellerInfoFieldState extends State<_SellerInfoField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SellerInfoField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.sellerId)
          .set({
            widget.fieldKey: _controller.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      if (widget.fieldKey == 'name') {
        await SellerSession.updateName(_controller.text.trim());
        if (!mounted) {
          return;
        }
      }
      FocusScope.of(context).unfocus();
      setState(() => _isEditing = false);
      AppToast.show(context, widget.savedMessage);
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Error: ${error.message ?? error.code}',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      final value = _controller.text.trim();
      return _SettingsDisplayField(
        label: widget.label,
        value: value,
        isEmpty: value.isEmpty,
        onEdit: () => setState(() => _isEditing = true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsEditHeader(
          label: widget.label,
          onCancel: () {
            _controller.text = widget.initialValue;
            FocusScope.of(context).unfocus();
            setState(() => _isEditing = false);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !_isSaving,
          keyboardType: widget.keyboardType,
          textInputAction: TextInputAction.done,
          inputFormatters: widget.inputFormatters,
          decoration: InputDecoration(
            hintText: widget.hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            height: 44,
            width: 104,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7801),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                )
                : const Text('Save'),
          ),
        ),
        ),
      ],
    );
  }
}

class _SettingsDisplayField extends StatelessWidget {
  const _SettingsDisplayField({
    required this.label,
    required this.value,
    required this.isEmpty,
    required this.onEdit,
  });

  final String label;
  final String value;
  final bool isEmpty;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                    fontWeight: value.trim().isEmpty
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              backgroundColor: isEmpty ? const Color(0xFFFF7801) : null,
              foregroundColor: isEmpty ? Colors.white : Colors.black,
              side: isEmpty
                  ? BorderSide.none
                  : BorderSide(color: Colors.grey.shade500),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(58, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isEmpty ? 'Add' : 'Edit',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsEditHeader extends StatelessWidget {
  const _SettingsEditHeader({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Update this information.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            padding: EdgeInsets.zero,
            minimumSize: const Size(54, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
  }
}
