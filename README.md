# Photo Booth Application

A Flutter photo booth application with AI transformations, built using MVVM architecture.

## Features

- Theme selection
- Camera selection (front/back)
- Photo capture
- AI-powered image transformation
- Photo review and editing
- Printing support
- WhatsApp sharing

## Architecture

- **MVVM Pattern**: Models, ViewModels, and Views are strictly separated
- **State Management**: Provider
- **Platform Support**: iOS and Android (phones and tablets)

## Getting Started

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── models/          # Data models
├── viewmodels/      # Business logic
├── views/
│   ├── screens/     # Full-page screens
│   └── widgets/     # Reusable components
├── services/        # External integrations
└── utils/           # Helpers and constants
```

## Testing

Run tests with:
```bash
flutter test
```

