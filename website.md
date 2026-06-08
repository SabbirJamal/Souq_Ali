# Bizsooq Website Handoff

This document describes the mobile website version needed for Bizsooq. The website should mirror the buyer-facing app flows: Feed, Live, Item Detail, and Seller Info/Profile.

## Global Mobile UI

- Background color: `#F4FBF7`.
- Status/header feel: black top system strip, then Bizsooq logo/header area.
- Primary orange: `#FF7801`.
- WhatsApp green: `#25D366`.
- Dark navy used for selected selectors/icons: `#001341`.
- Cards use white surfaces, soft shadow, and rounded corners around `8-10px`.
- Floating search button is orange circular `44x44`; when opened, it expands into a white rounded search bar with orange border.
- Toast/pop-up alerts are floating near top: white rounded rectangle, black text, black border, about `95%` width, disappears after about 2 seconds.
- Bottom navigation on app has Home, Live, Add, Listings, Settings. Website buyer pages only need navigation between Feed, Live, and profile/detail paths unless seller features are included later.

## Database Collections

### `items`

Each post/live item is stored in `items`.

Important fields:

- `item_name`: string.
- `item_price`: string, formatted with OMR and unit when price exists.
- `location`: string. Transit posts may store `🚚 Transit`.
- `is_transit`: boolean. If true, hide price and show transit location with truck icon only once.
- `status`: string, either `post` or `live`.
- `created_at`: Firestore timestamp.
- `expires_at`: Firestore timestamp.
- `seller_uid`: seller document id or phone-based id.
- `seller_phone`: seller phone number.
- `seller_name`: seller display name.
- `seller_cr`: CR number if available.
- `image_urls`: legacy list of image URLs.
- `media_files`: preferred media array. Each entry:
  - `url`: media URL.
  - `type`: `image` or `video`.
  - `thumbnail_url`: thumbnail URL, especially important for videos.

Expiry rules:

- `status = post`: current app adds expiry at 18 hours.
- `status = live`: current app adds expiry at 2 hours.
- Expired items should not show in feed/live/detail.

### `sellers`

Seller profile documents.

Important fields:

- `name`
- `cr_number` or `crNumber`
- `location`
- phone number can come from document id or stored phone fields depending on existing data.

### Seen Tracking

Used to avoid showing already-seen posts at the top.

Preferred collection:

- `viewer_seen/{viewerId}/items/{itemId}`

Legacy mirror:

- `item_seen/{itemId}/viewers/{viewerId}`

Fields:

- `item_id`
- `viewer_id`
- `viewer_type`: `seller` or `anonymous`
- `seller_id`: only for sellers
- `seen_at`

For website, create or reuse a stable viewer id:

- If logged in seller: use seller id or phone/session id.
- If buyer/anonymous: use anonymous auth uid or stable browser id.

## Backend/API Logic

The app uses Firebase Cloud Functions rather than loading all items directly.

### `getFeedItems`

Callable function in region `us-central1`.

Input:

```json
{
  "viewerId": "string",
  "status": "post | live",
  "cursor": {
    "createdAtMs": 123,
    "docId": "itemDocId"
  },
  "limit": 60
}
```

Behavior:

- Fetches items ordered by `created_at desc`.
- Filters by `status`.
- Filters expired items.
- Reads seen ids from `viewer_seen`.
- Returns unseen items first.
- If no unseen items are left, returns seen items as fallback.
- Returns a cursor for pagination.

Response:

```json
{
  "items": [
    {
      "id": "itemId",
      "data": {}
    }
  ],
  "cursor": {},
  "hasMore": true
}
```

### `markFeedItemsSeen`

Callable function in region `us-central1`.

Input:

```json
{
  "viewerId": "string",
  "viewerType": "seller | anonymous",
  "itemIds": ["itemId1", "itemId2"]
}
```

Behavior:

- Writes seen records to both `item_seen` and `viewer_seen`.
- Batch limit is capped server-side.
- Website should call this after item cards are visibly seen.

Recommended web visibility rule:

- Mark card as seen when at least around `35%` of card height is visible.
- Debounce seen writes around `800ms`.
- Before manual refresh, flush pending seen writes first.

## Feed Page

Purpose: Show normal posts where `status = post`.

Mobile UI:

- Header at top with Bizsooq logo centered.
- Floating orange search button on top right.
- Search expands to full-width rounded white input with orange border.
- Grid/list toggle icon on header.
- Default layout is 2-column grid.
- Background is `#F4FBF7`.
- Cards have small spacing:
  - Grid columns: 2.
  - Horizontal gap: about `4px`.
  - Vertical gap: about `2px`.
  - Outer horizontal padding: about `2px`.
- Pull to refresh reloads feed.
- Infinite scroll loads more when near bottom.
- Skeleton cards show while initial data loads.
- If empty, show `No items available`.

Feed behavior:

- Fetch via `getFeedItems(status: post, limit: 60)`.
- Search is local on currently loaded items by item name, price, and location.
- Search input debounce: about `280ms`.
- Keep loaded cards alive while scrolling so already loaded media does not reload until refresh/app restart.

Item card UI:

- Full card is tappable and opens Item Detail page.
- Card media:
  - Show only first media item.
  - If first media is video, show thumbnail image with centered play icon.
  - Videos must not play in feed for performance.
  - Use optimized image sizes/caching.
- Top left:
  - Media count badge for images/videos.
  - If item is live and not on live page, show small LIVE badge below count.
- Top right:
  - Uploaded age badge like `just now`, `15 min ago`, `3 hrs ago`.
- Bottom overlay:
  - White chips over the image.
  - Order:
    1. Location
    2. Price, if exists and not transit
    3. Item name
  - If transit:
    - show truck icon and Transit text.
    - do not show price.
  - If no price:
    - do not show price field.

## Live Page

Purpose: Show live posts where `status = live`.

Mobile UI:

- Same base layout as Feed page.
- Empty message: `No live items available`.
- Uses the same 2-column grid/card layout.
- Live cards should feel identical to feed cards, except live indicators replace uploaded-age display.

Live behavior:

- Fetch via `getFeedItems(status: live, limit: 60)`.
- Same pagination, refresh, search, seen tracking, and keep-alive behavior as Feed.

Live card differences:

- Top right: show live animation/badge instead of uploaded age.
- Under or near live badge, show expiry text if available/implemented, e.g. `Exp in 1 Hr`.
- Remove duplicate live icon from top left if top-right live badge is used.
- Still show media count top left.
- Card opens Item Detail page.

## Item Detail Page

Purpose: Show full item media, item details, seller info, and contact actions.

Mobile UI:

- Top black system strip.
- Floating circular white back button at top left.
- Media header height: about `80%` of screen height.
- Media is first viewport content.
- Below media:
  - Seller info row.
  - Fixed black contact/action bar at bottom.

Media behavior:

- Use `media_files` first. Fall back to `image_urls`.
- Supports multiple media with horizontal swipe.
- Swipe should tolerate imperfect horizontal gestures, not require perfectly straight swipe.
- For images:
  - Use `BoxFit.contain` for detail media.
  - Portrait media should fit frame well.
  - Landscape media may show black/empty side or top/bottom space.
  - Pinch zoom works horizontally, vertically, or diagonally.
  - During zoom, item info overlays disappear.
  - Hold on media hides item info.
- For videos:
  - Videos autoplay when detail page opens if current media is video.
  - Videos loop.
  - Audio is enabled.
  - Tap video to pause/play.
  - Paused/playing icon overlay should be average size, not huge.
  - Swiping to another media stops previous video.
  - Leaving/backing out of detail stops video/audio.
  - Video can be zoomed while playing or paused; item info hides while zooming.

Media overlay info:

- Media count badge should appear bottom left.
- Live items show live animation/badge top right aligned horizontally with media count styling.
- Item info over media uses white chips and same order as feed:
  1. Location
  2. Price if available and not transit
  3. Item name
- Transit location should show truck icon and Transit text only once.
- No price means no price chip.

Seller info below media:

- Shows seller name and CR number as:
  - `SELLER NAME | CR No. 12345`
- Shows formatted phone below.
- Seller info is clickable and opens Seller Info/Profile page.

Bottom fixed action bar:

- Black background.
- Three buttons:
  - Call: blue button with phone icon.
  - WhatsApp: green button with WhatsApp icon.
  - Share: orange button with white `Share` text.
- Buttons are rounded rectangles with about `10px` radius.

Performance:

- Preload first video controller on detail load.
- Pre-cache media thumbnails/images.
- Show warmup skeleton briefly while detail media prepares.
- Dispose/pause videos when leaving page.

## Seller Info/Profile Page

Purpose: Show seller details and seller posts.

Mobile UI:

- Background `#F4FBF7`.
- Top black status strip.
- Bizsooq logo/header.
- If opened from item detail, show floating circular back button.
- Seller identity section:
  - Seller name.
  - CR number.
  - Phone number.
- Share button:
  - Orange background.
  - White text.
  - Floating/header area.
- Post selector:
  - Two segmented tabs:
    - `POSTINGS`
    - `LIVE`
  - Selected tab has orange background.
  - Unselected tab white.
  - Rounded outer edges and selected segment should also look rounded.
- Seller cards use the same item card UI as feed/home.

Seller profile data:

- Read seller document from `sellers/{sellerId}`.
- If seller name missing, use fallback name from item.
- CR number can be `cr_number` or `crNumber`.

Seller posts:

- For `POSTINGS`, query items where:
  - seller matches current seller id/phone.
  - `status = post`.
  - not expired.
- For `LIVE`, query items where:
  - seller matches.
  - `status = live`.
  - not expired.
- Item cards open Item Detail page.
- If no posts, show empty state.

## Media/Image Rules

- Always prefer `media_files`.
- Use `thumbnail_url` for feed/live cards, especially for videos.
- Feed/live should never stream full videos inside cards.
- Detail page can stream/play video.
- Use cache/downscaled image loading:
  - Compact card images around 500-720px cache width.
  - Larger detail images around 1200-1600px cache width.
- Use skeleton placeholders while loading.
- Keep cards alive during scroll to avoid reloading when scrolling back up.

## Search

- Search is local on loaded feed/live items.
- Search fields:
  - `item_name`
  - `item_price`
  - `location`
- Debounce input.
- Search does not need to call backend unless implementing full search later.

## Share

Share should use item id and item data to create a shareable item page/link. App has a `ShareListingPage`; website should expose public item detail URLs like:

```text
/item/{itemId}
```

## Expiry And Cleanup

- App hides expired items using `expires_at`.
- Cloud Function cleanup deletes expired items every 6 hours.
- Cleanup also deletes storage media files and seen records.
- Website should still filter expired items client/server-side because cleanup may run later.

## Recommended Website Routes

```text
/              Feed page, status=post
/live          Live page, status=live
/item/:itemId  Item detail page
/seller/:id    Seller info/profile page
```

## Website Implementation Notes

- Use Firebase Auth anonymous sign-in or a stable browser id for buyer seen tracking.
- Use callable functions:
  - `getFeedItems`
  - `markFeedItemsSeen`
- Do not fetch thousands of Firestore documents directly in browser.
- Use infinite scroll and virtualized rendering for feed/live.
- Mark seen cards using IntersectionObserver with threshold around `0.35`.
- Keep loaded cards cached in page state until refresh.
- Use lazy image loading and video thumbnails.
- Only load/play video on detail page.
- Stop video/audio on route change.
- Keep mobile-first layout first; desktop can center content in a max-width container later.
