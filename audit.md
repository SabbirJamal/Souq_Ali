# Feed Image Prefetch Plan

Read-only audit. No implementation was done.

## 1. Exact Code Location Where Prefetch Would Be Added

Primary location:

- `lib/seller_tabs/seller_feed_tab.dart`
- Method: `_fetchPage`
- After feed response is merged into `_allDocs`

Current code area:

```dart
final result = await FeedService.fetchItems(
  viewerId: viewerId,
  status: widget.itemStatus,
  cursor: isInitial ? null : _feedCursor,
  limit: requestedLimit,
);
if (!mounted) return;
setState(() {
  if (isInitial) {
    _allDocs.clear();
  }
  final existingIds = _allDocs.map((doc) => doc.id).toSet();
  _allDocs.addAll(result.items.where((doc) => !existingIds.contains(doc.id)));
  _feedCursor = result.cursor;
  _hasMore = result.hasMore || result.items.length >= requestedLimit;
  _isLoading = false;
  _cachedFilteredDocs = null;
});
_scheduleVisibleSeenCheck();
```

Exact line references from current file:

- `lib/seller_tabs/seller_feed_tab.dart:133` feed request
- `lib/seller_tabs/seller_feed_tab.dart:140` `setState`
- `lib/seller_tabs/seller_feed_tab.dart:145` `_allDocs.addAll(...)`
- `lib/seller_tabs/seller_feed_tab.dart:151` `_scheduleVisibleSeenCheck()`

Safest insertion point:

- Immediately after `setState(...)`
- Before `_scheduleVisibleSeenCheck()`

Reason:

- The feed data has already arrived.
- `_allDocs` now contains the exact items that will render.
- `context` is available for `precacheImage`.
- UI behavior does not need to change.

## 2. Exact Flutter API That Would Be Used

Flutter API:

```dart
precacheImage(ImageProvider provider, BuildContext context)
```

Provider:

```dart
CachedNetworkImageProvider(
  url,
  maxWidth: 500,
)
```

Why this provider:

- Feed already uses `CachedNetworkImage`.
- `CachedNetworkImageProvider` uses the same cache ecosystem.
- `maxWidth` should match or stay close to feed card memory decode width.

Existing detail page already uses similar API:

- `lib/item_detail_page.dart:81`

```dart
precacheImage(
  CachedNetworkImageProvider(url, maxWidth: 1600),
  context,
);
```

Feed should use a lower max width than detail because feed cards are smaller.

## 3. Estimated Memory Impact

Current feed image config:

- Compact card `memCacheWidth`: `500`
- Compact card `maxWidthDiskCache`: `720`

Location:

- `lib/widgets/media_carousel.dart:151`
- `lib/widgets/media_carousel.dart:152`

Approx decoded memory estimate:

```text
decoded bytes = width * height * 4
```

If a thumbnail is around 500px wide:

- Square-ish 500 x 500 = about 1 MB decoded
- Portrait-ish 500 x 900 = about 1.8 MB decoded
- Four images = around 4 to 8 MB
- Six images = around 6 to 11 MB
- Eight images = around 8 to 15 MB

Actual memory depends on aspect ratio and decoded dimensions.

Safe range:

- 4 thumbnails: low memory risk
- 6 thumbnails: balanced
- 8 thumbnails: still usually acceptable, but more pressure on low-end phones

## 4. Estimated Network Impact

Network impact depends on whether URL points to:

- backend optimized thumbnail, usually around 520px
- app-generated thumbnail, up to 720px
- full image fallback, if `thumbnail_url` is missing

Known thumbnail sizes from code:

- backend optimized thumbnail width: `520`
  - `media_processor/index.js:21`

- app-generated image thumbnail: `720`, quality `36`
  - `lib/seller_tabs/seller_add_item_tab.dart:326`

Rough impact:

- 4 optimized thumbnails: low
- 6 optimized thumbnails: moderate but safe
- 8 optimized thumbnails: higher, may compete with visible image loads

Important risk:

- If `thumbnail_url` is missing and prefetch falls back to full `url`, network usage can jump significantly.

Safest rule:

- Prefetch `thumbnail_url` first.
- Only fallback to full `url` for first visible items, not for all prefetched items.

## 5. How Many Thumbnails Should Be Prefetched

Recommended starting point:

- Prefetch first 6 thumbnail URLs.

Reason:

- Grid shows around 4 cards on screen.
- 6 covers the first viewport plus a small buffer.
- Lower risk than 8 on low-memory devices.
- Better visual improvement than 4.

## 6. Why 4, 6, Or 8 Is Safest

### 4 Thumbnails

Pros:

- Lowest memory impact.
- Lowest network impact.
- Safest for weaker phones.

Cons:

- Only covers the first visible grid.
- User may still see placeholders immediately after the first screen.

Best if:

- Client is worried about RAM/data usage.

### 6 Thumbnails

Pros:

- Covers first visible cards plus a small scroll buffer.
- Good balance between speed and resource usage.
- Safer than prefetching the full initial 16.

Cons:

- Slightly more network and memory than 4.

Best default:

- Yes. This is the recommended production starting value.

### 8 Thumbnails

Pros:

- More aggressive.
- Better if users scroll immediately after feed opens.

Cons:

- Higher memory and network pressure.
- More concurrent Firebase Storage requests.
- Could slow lower-end devices if cache is cold.

Best if:

- Real-device testing shows 6 is not enough.

## 7. Implementation Plan Only

No code implemented yet.

### Step 1

Add an import to `seller_feed_tab.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
```

### Step 2

After `_allDocs` is updated in `_fetchPage`, schedule a non-blocking prefetch.

Important:

- Do not `await` prefetch inside feed loading.
- Do not delay UI.
- Do not change pagination.

Suggested pattern:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _prefetchFeedThumbnails(result.items);
});
```

### Step 3

Create helper method in `SellerFeedTabState`:

```dart
void _prefetchFeedThumbnails(List<FeedItem> items) {
  // collect first 6 thumbnail URLs
  // call precacheImage with CachedNetworkImageProvider
}
```

### Step 4

Use existing parser:

```dart
final media = mediaItemsFromMap(item.data);
```

Then select:

```dart
final url = first.thumbnailUrl?.trim().isNotEmpty == true
    ? first.thumbnailUrl!.trim()
    : first.url.trim();
```

Safer production rule:

- Prefer thumbnail URL.
- Fallback to full URL only for first 4 items.
- Skip empty URLs.
- Deduplicate URLs with a small `Set<String>`.

### Step 5

Use:

```dart
precacheImage(
  CachedNetworkImageProvider(url, maxWidth: 500),
  context,
).catchError((_) {});
```

Do not throw errors if prefetch fails.

### Step 6

Keep prefetch scoped:

- Initial load: prefetch 6
- Pagination load: optionally prefetch 4 from the newly returned page

Safest initial implementation:

- Prefetch only after initial load.

More complete implementation:

- Initial load: 6
- Pagination: 4

### Step 7

Avoid repeated prefetch:

Maintain a local set:

```dart
final Set<String> _prefetchedImageUrls = {};
```

Skip URLs already prefetched during this feed session.

## Recommended Final Plan

Use 6 as the initial prefetch count.

Implementation should:

- prefetch only thumbnails where possible
- avoid awaiting prefetch
- deduplicate URLs
- cap decode width to 500
- ignore errors
- not change UI
- not change feed query
- not change pagination
- not change Firebase Auth or schema

Expected result:

- First visible feed images should appear sooner after feed data arrives.
- Placeholders should disappear faster on cold loads.
- Memory/network impact should remain controlled.
