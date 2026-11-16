# SS Maps

A cross-platform mobile navigation application built with Flutter and geospatial location APIs, delivering real-time location tracking, place search, and route navigation across Android and iOS devices.

## Key Features

- Real-Time GPS Tracking: Live device geolocation and dynamic map camera updates.
- Route and Turn-by-Turn Navigation: Optimal path calculation, distance/ETA estimation, and polyline route rendering between origin and destination.
- Place Search and Geocoding: Fast address lookup, autocomplete suggestions, and coordinate-to-address reverse geocoding.
- Cross-Platform Performance: Single Flutter codebase compiled natively for Android and iOS.

## Tech Stack

- Framework: Flutter (Dart)
- Geospatial and Mapping: Location and Maps APIs, Geolocator, Geocoding
- Platforms: Android, iOS, Web
- Version Control: Git and GitHub

## Project Structure

SS_Map/
├── android/          Android native configuration and Gradle files
├── ios/              iOS native configuration and Runner
├── lib/              Core Dart application code (UI, map logic, API services)
├── test/             Widget and unit tests
├── pubspec.yaml      Flutter dependencies and asset declarations
└── README.md         Project documentation

## Getting Started

Prerequisites:
- Flutter SDK (3.x or higher)
- Android Studio / Xcode or VS Code with Flutter and Dart extensions
- A valid Maps / Geospatial API key

Installation and Setup:

1. Clone the repository:
   git clone https://github.com/MR-SOLU/ss-maps.git
   cd ss-maps

2. Install dependencies:
   flutter pub get

3. Configure API Keys:
   Create a .env file in the root directory (or configure android/local.properties) and add your geospatial API key:
   MAPS_API_KEY=your_api_key_here

4. Run the application:
   flutter run

## Author

Solai Raj S
GitHub: https://github.com/MR-SOLU
