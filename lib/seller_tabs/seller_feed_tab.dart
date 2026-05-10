import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/item_card.dart';

class SellerFeedTab extends StatefulWidget {
  const SellerFeedTab({super.key});

  @override
  State<SellerFeedTab> createState() => _SellerFeedTabState();
}

class _SellerFeedTabState extends State<SellerFeedTab> {
  final _searchController = TextEditingController();
  Timer? _clockTimer;
  bool _isSearchOpen = false;
  bool _isGridView = false;
  String _query = '';
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearchOpen = false;
      _query = '';
    });
  }

  void _toggleLayoutMode() {
    setState(() => _isGridView = !_isGridView);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return docs;
    }

    return docs.where((doc) {
      final item = doc.data();
      final searchableText = [
        item['item_name'],
        item['item_price'],
        item['origin'],
        item['location'],
      ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(
        ' ',
      );
      return searchableText.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final docs = _filterDocs(
          (snapshot.data?.docs ?? [])
              .where((doc) => _isItemActive(doc.data(), _now))
              .toList(),
        );

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _FeedHeader(
                isSearchOpen: _isSearchOpen,
                searchController: _searchController,
                onOpenSearch: _openSearch,
                onCloseSearch: _closeSearch,
                onQueryChanged: (value) => setState(() => _query = value),
                isGridView: _isGridView,
                onToggleGrid: _toggleLayoutMode,
              ),
            ),
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: ${snapshot.error}')),
              )
            else if (docs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No items available',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: _isGridView
                    ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                    : const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
                sliver: _isGridView
                    ? SliverToBoxAdapter(child: _MasonryItemGrid(docs: docs))
                    : SliverList.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ItemCard(docId: doc.id, item: doc.data());
                        },
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _MasonryItemGrid extends StatelessWidget {
  const _MasonryItemGrid({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    final leftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final rightDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (var i = 0; i < docs.length; i++) {
      if (i.isEven) {
        leftDocs.add(docs[i]);
      } else {
        rightDocs.add(docs[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _MasonryColumn(docs: leftDocs)),
        const SizedBox(width: 4),
        Expanded(child: _MasonryColumn(docs: rightDocs)),
      ],
    );
  }
}

class _MasonryColumn extends StatelessWidget {
  const _MasonryColumn({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs.map((doc) {
        return ItemCard(docId: doc.id, item: doc.data(), isCompact: true);
      }).toList(),
    );
  }
}

bool _isItemActive(Map<String, dynamic> item, DateTime now) {
  final expiresAt = item['expires_at'];
  if (expiresAt is Timestamp) {
    return expiresAt.toDate().isAfter(now);
  }
  if (expiresAt is DateTime) {
    return expiresAt.isAfter(now);
  }
  return true;
}

class _GridToggleButton extends StatelessWidget {
  const _GridToggleButton({
    required this.isGridView,
    required this.onTap,
    this.bottomPadding = 23,
  });

  final bool isGridView;
  final VoidCallback onTap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Material(
        color: const Color(0xFF1877F2),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              isGridView ? Icons.view_agenda : Icons.grid_view,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.isSearchOpen,
    required this.searchController,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onQueryChanged,
    required this.isGridView,
    required this.onToggleGrid,
  });

  final bool isSearchOpen;
  final TextEditingController searchController;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQueryChanged;
  final bool isGridView;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFF7801),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'BIZ SOOQ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: isSearchOpen ? constraints.maxWidth - 56 : 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: isSearchOpen
                              ? Row(
                                  key: const ValueKey('search-field'),
                                  children: [
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.search,
                                      color: Color(0xFFFF7801),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: searchController,
                                        autofocus: true,
                                        onChanged: onQueryChanged,
                                        decoration: const InputDecoration(
                                          hintText: 'Search items...',
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: onCloseSearch,
                                      icon: const Icon(Icons.close),
                                      color: const Color(0xFFFF7801),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  key: const ValueKey('search-button'),
                                  onPressed: onOpenSearch,
                                  icon: const Icon(Icons.search),
                                  color: const Color(0xFFFF7801),
                                ),
                        ),
                      ),
                    ),
                    if (!isSearchOpen)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _GridToggleButton(
                          isGridView: isGridView,
                          onTap: onToggleGrid,
                          bottomPadding: 0,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
    );
  }
}
