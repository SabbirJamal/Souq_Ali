import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../app_toast.dart';

class MediaPickerSheet extends StatefulWidget {
  const MediaPickerSheet({
    super.key,
    required this.selectedIds,
    required this.selectedCount,
    required this.maxCount,
    required this.onAssetsDone,
    this.maxSelectionMessage = 'Only 8 media can be selected',
  });

  final Set<String> selectedIds;
  final int selectedCount;
  final int maxCount;
  final String maxSelectionMessage;
  final Future<void> Function(List<AssetEntity> assets, Set<String> selectedIds)
  onAssetsDone;

  @override
  State<MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<MediaPickerSheet> {
  static const _pageSize = 90;
  static const _preferredAlbumOrder = {
    'camera': 1,
    'cameraroll': 1,
    'videos': 2,
    'video': 2,
    'screenshots': 3,
    'screenshot': 3,
    'download': 4,
    'downloads': 4,
  };

  final Set<String> _selectedIds = {};
  final Map<String, int> _selectedOrder = {};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  final List<AssetEntity> _pendingAssets = [];
  List<AssetPathEntity> _albums = [];
  List<AssetEntity> _assets = [];
  AssetPathEntity? _selectedAlbum;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreAssets = true;
  bool _hasPermission = true;
  bool _hasLimitedPermission = false;
  bool _maxSelectionMessageShown = false;
  bool _isMaxSelectionMessageVisible = false;
  int _currentPage = 0;
  int _loadToken = 0;
  Timer? _maxSelectionMessageTimer;

  int get _currentTotalSelectionCount =>
      widget.selectedCount - widget.selectedIds.length + _selectedIds.length;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.selectedIds);
    _rebuildSelectedOrder();
    _loadAssets();
  }

  @override
  void dispose() {
    _maxSelectionMessageTimer?.cancel();
    super.dispose();
  }

  void _rebuildSelectedOrder() {
    _selectedOrder
      ..clear()
      ..addEntries(
        _selectedIds.toList().asMap().entries.map(
              (entry) => MapEntry(entry.value, entry.key + 1),
            ),
      );
  }

  Future<Uint8List?> _thumbnailFor(AssetEntity asset, ThumbnailSize size) {
    return _thumbnailFutures.putIfAbsent(
      '${asset.id}-${size.width}-${size.height}',
      () => asset.thumbnailDataWithSize(size),
    );
  }

  Future<void> _loadAssets() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      return;
    }

    final hasLimitedPermission = permission == PermissionState.limited;
    final albums = await _loadMediaAlbums();
    if (albums.isEmpty) {
      setState(() {
        _hasLimitedPermission = hasLimitedPermission;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _albums = albums;
      _selectedAlbum = albums.first;
      _hasLimitedPermission = hasLimitedPermission;
      _isLoading = false;
    });
    await _loadFirstAlbumPage();
  }

  Future<List<AssetPathEntity>> _loadMediaAlbums() async {
    final albumsById = <String, AssetPathEntity>{};
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    for (final album in albums) {
      if (album.isAll || _preferredAlbumOrder.containsKey(_albumKey(album))) {
        albumsById[album.id] = album;
      }
    }
    final sortedAlbums = albumsById.values.toList();
    sortedAlbums.sort((first, second) {
      if (first.isAll != second.isAll) {
        return first.isAll ? -1 : 1;
      }
      final firstRank = _albumRank(first);
      final secondRank = _albumRank(second);
      if (firstRank != secondRank) {
        return firstRank.compareTo(secondRank);
      }
      return first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });
    return sortedAlbums;
  }

  int _albumRank(AssetPathEntity album) =>
      album.isAll ? 0 : _preferredAlbumOrder[_albumKey(album)] ?? 99;

  String _albumKey(AssetPathEntity album) =>
      album.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _changeAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) {
      return;
    }
    setState(() {
      _selectedAlbum = album;
      _assets = [];
      _currentPage = 0;
      _hasMoreAssets = true;
      _isLoadingMore = false;
    });
    await _loadFirstAlbumPage();
  }

  Future<void> _loadFirstAlbumPage() async {
    final token = ++_loadToken;
    setState(() {
      _assets = [];
      _currentPage = 0;
      _hasMoreAssets = true;
      _isLoadingMore = true;
    });
    await _loadMoreAssets(token: token);
  }

  Future<void> _loadMoreAssets({int? token}) async {
    final album = _selectedAlbum;
    if (album == null || _isLoadingMore && token == null || !_hasMoreAssets) {
      return;
    }

    final activeToken = token ?? _loadToken;
    if (token == null) {
      setState(() => _isLoadingMore = true);
    }

    final nextAssets = await album.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );
    if (!mounted || activeToken != _loadToken) {
      return;
    }

    final visibleAssets = nextAssets
        .where(
          (asset) => asset.type == AssetType.image || asset.type == AssetType.video,
        )
        .toList();

    setState(() {
      _assets.addAll(visibleAssets);
      _currentPage += 1;
      _hasMoreAssets = nextAssets.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  void _maybeLoadMore(int index) {
    if (index >= _assets.length - 18 && _hasMoreAssets && !_isLoadingMore) {
      _loadMoreAssets();
    }
  }

  Future<void> _toggleAsset(AssetEntity asset) async {
    if (_selectedIds.contains(asset.id)) {
      setState(() {
        _selectedIds.remove(asset.id);
        _pendingAssets.removeWhere((pending) => pending.id == asset.id);
        if (_currentTotalSelectionCount < widget.maxCount) {
          _maxSelectionMessageShown = false;
        }
        _rebuildSelectedOrder();
      });
      return;
    }

    if (_currentTotalSelectionCount >= widget.maxCount) {
      _showMaxSelectionMessage();
      return;
    }
    if (asset.type == AssetType.video && asset.duration > 60) {
      AppToast.show(context, 'Video cannot be more than 1 minute');
      return;
    }

    setState(() {
      _selectedIds.add(asset.id);
      _pendingAssets.add(asset);
      if (_currentTotalSelectionCount < widget.maxCount) {
        _maxSelectionMessageShown = false;
      }
      _rebuildSelectedOrder();
    });
  }

  void _showMaxSelectionMessage() {
    if (_maxSelectionMessageShown) {
      return;
    }
    _maxSelectionMessageShown = true;
    _maxSelectionMessageTimer?.cancel();
    setState(() => _isMaxSelectionMessageVisible = true);
    _maxSelectionMessageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isMaxSelectionMessageVisible = false);
      }
    });
  }

  Future<void> _finishSelection() async {
    await widget.onAssetsDone(_pendingAssets, Set<String>.from(_selectedIds));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    if (_isLoading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!_hasPermission)
                      SliverFillRemaining(child: _buildPermissionDenied())
                    else
                      ...[
                        if (_hasLimitedPermission)
                          SliverToBoxAdapter(
                            child: _buildLimitedAccessNotice(),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 92),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final asset = _assets[index];
                              _maybeLoadMore(index);
                              return _AssetTile(
                                asset: asset,
                                thumbnailFuture: _thumbnailFor(
                                  asset,
                                  const ThumbnailSize.square(240),
                                ),
                                selectionNumber: _selectedOrder[asset.id],
                                onTap: () => _toggleAsset(asset),
                              );
                            }, childCount: _assets.length),
                          ),
                        ),
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 96),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                  ],
                ),
                if (_pendingAssets.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: SafeArea(
                      child: Container(
                        height: 68,
                        color: Colors.black,
                        padding: const EdgeInsets.fromLTRB(8, 7, 86, 7),
                        child: SizedBox(
                          height: 54,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _pendingAssets.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final asset = _pendingAssets[index];
                              return _SelectedAssetPreview(
                                asset: asset,
                                thumbnailFuture: _thumbnailFor(
                                  asset,
                                  const ThumbnailSize(90, 120),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: SafeArea(
                    child: FloatingActionButton(
                      heroTag: 'media_done',
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.black,
                      onPressed: _finishSelection,
                      child: const Icon(Icons.check),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: _pendingAssets.isEmpty ? 92 : 84,
                  child: SafeArea(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _isMaxSelectionMessageVisible
                          ? _PickerLimitMessage(widget.maxSelectionMessage)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2D2F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAlbum?.id,
                    dropdownColor: const Color(0xFF2A2D2F),
                    iconEnabledColor: Colors.white,
                    isExpanded: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    items: _albums
                        .map(
                          (album) => DropdownMenuItem<String>(
                            value: album.id,
                            child: Text(
                              album.isAll ? 'Recent' : album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (albumId) {
                      if (albumId == null) {
                        return;
                      }
                      final album = _albums.firstWhere(
                        (album) => album.id == albumId,
                        orElse: () => _albums.first,
                      );
                      _changeAlbum(album);
                    },
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _finishSelection,
            child: Text(
              _currentTotalSelectionCount == 0
                  ? 'Done'
                  : 'Done ($_currentTotalSelectionCount)',
              style: const TextStyle(color: Color(0xFF25D366)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library, color: Colors.white70, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Allow photo access to choose item media.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitedAccessNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF252A28),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Only selected media is visible. Allow full gallery access in settings.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.thumbnailFuture,
    required this.selectionNumber,
    required this.onTap,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbnailFuture;
  final int? selectionNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FutureBuilder<Uint8List?>(
                future: thumbnailFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Container(color: const Color(0xFF252A28));
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
            ),
            if (asset.type == AssetType.video)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.play_circle_fill, color: Colors.white),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: selectionNumber != null
                    ? const Color(0xFF25D366)
                    : Colors.black54,
                child: Text(
                  selectionNumber?.toString() ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedAssetPreview extends StatelessWidget {
  const _SelectedAssetPreview({
    required this.asset,
    required this.thumbnailFuture,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbnailFuture;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 42,
          height: 54,
          child: FutureBuilder<Uint8List?>(
            future: thumbnailFuture,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(color: const Color(0xFF252A28));
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }
}

class _PickerLimitMessage extends StatelessWidget {
  const _PickerLimitMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
