# Performance And Architecture Notes

Building a high-performance, professional app requires moving away from "just making it work" to "designing for scale." Since more development is planned, this is a professional architecture and strategy guide for the project.

## 1. Architecture: The "Feature-First" Approach

As the app grows, avoid putting files into generic folders like `lib/widgets` or `screens/`. Instead, use a Feature-First structure.

- Concept: Group everything related to a single user goal, like Authentication, Item Feed, or Camera, into its own folder.
- Placement: Inside `lib`, create a `features/` folder. Each feature folder should have its own:
  - `ui/`: Screens and local widgets.
  - `logic/`: Controllers or state management.
  - `models/`: Data structures.
- Why: This prevents file sprawl. If the Add Item flow needs to change, the related files are easy to find without searching through many unrelated files.

## 2. Frontend And Design Strategy

- Atomic Design: Break UI into the smallest possible parts. An atom is a button, a molecule is a price chip, and an organism is an item card. Build organisms using atoms.
- State Management Strategy: Avoid using `setState()` in main page files when possible, because it can force the entire screen to rebuild.
- Use Localized State: If only a timer is changing, only that timer widget should rebuild.
- Use Service-View Separation: UI should not know how to talk to Firestore directly. It should call a method in a separate service or controller, which returns the data.
- Design Tokens: Instead of typing `Color(0xFFFF7801)` everywhere, define an `AppColors` class. Instead of repeated `16.0` padding, use something like `AppSpacing.medium`. This makes global design changes much faster.

## 3. Backend And Database Strategy: Firestore

- Index-Driven Queries: Firestore is fast only if queries are correct. Filter data at the database level using `.where()` instead of fetching many items and filtering inside the app.
- Flatten Data: Firestore is not relational. It can be better to duplicate small data, like seller name inside the item document, instead of doing another query later.
- The Rule Of 15: Never load more than 15-20 items in a list at once. Use pagination or infinite scroll to save user data, memory, and battery.
- Cold Start Optimization: Load critical data like user session and theme in parallel during splash so the user sees less loading after entering the app.

## 4. High-Performance Coding Style

- The Const Rule: Use `const` whenever possible. It tells Flutter not to recalculate immutable widgets, reducing CPU work during scrolling.
- File Length Limit: Aim for a maximum of around 300 lines per file. If a file is much longer, extract widgets or logic into separate files.
- Repaint Boundaries: Wrap complex animations, like the Lottie Live badge, in `RepaintBoundary` so animations do not force the rest of the screen to repaint every frame.
- Image Optimization: Never display a 5MB image in a 200px box. Use `memCacheWidth` so the phone decodes the image at a smaller size, saving RAM.

## 5. Deployment And Maintenance

- Environment Separation: Use separate Development and Production Firebase projects as the app grows. Avoid testing new features on live user data.
- Crash Analytics: Integrate Firebase Crashlytics early. It helps identify the exact crash line on user devices.
- Asset Discipline: Use `.webp` for images and `.json` for animations. Avoid large `.png` and `.mp4` assets inside the app package because they increase app size.

## Summary: The Professional Mindset

The difference between a hobbyist app and a commercial app is predictability.

1. Predictable UI: Proportions always match, using ratios and shared design rules.
2. Predictable Logic: UI only displays data; logic fetches and prepares data.
3. Predictable Speed: Data is paginated and images are cached.

Following these architecture rules helps the app stay fast and manageable as it grows to more users and more features.
