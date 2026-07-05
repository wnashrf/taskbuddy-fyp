# TaskBuddy

TaskBuddy is a collaborative task management application built with Flutter and Firebase, featuring AI-powered task decomposition using Google Gemini.

## 🚀 Features

- **AI Task Splitting**: Automatically decompose complex project questions into manageable subtasks using Google Gemini AI.
- **Collaborative Groups**: Create groups for course assignments, invite members, and manage tasks collectively.
- **Real-time Synchronization**: Powered by Cloud Firestore for instant updates across all devices.
- **File Attachments**: Upload and manage project-related documents and images using Firebase Storage.
- **Individual & Group Modes**: Support for both personal study tasks and collaborative group projects.
- **Activity Logs**: Track group progress and contributions with a detailed activity feed.
- **Centralized Theming**: Consistent UI across the app using a managed global theme.

## 📂 Project Structure

The project follows a production-grade layered architecture:

```text
lib/
├── core/                # App-wide constants, themes, and utilities
│   ├── constants/       # API endpoints, global keys
│   └── theme/           # App styling and color schemes
├── data/                # Data layer
│   ├── models/          # Data classes and JSON serialization (Planned)
│   └── services/        # Firebase and AI service implementations
├── ui/                  # Presentation layer
│   ├── screens/         # Full-page UI components
│   ├── widgets/         # Reusable UI components
│   └── shell.dart       # Main navigation shell
└── main.dart            # Application entry point
```

## 🛠️ Setup & Installation

### Prerequisites
- Flutter SDK (latest stable version)
- Firebase Project
- Google Gemini API Key

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/TaskBuddy.git
   cd TaskBuddy
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Environment Variables:**
   Create a `.env` file in the `assets/` directory:
   ```env
   GEMINI_API_KEY=your_api_key_here
   ```

4. **Firebase Setup:**
   - Configure your Android/iOS apps in the Firebase Console.
   - Replace `google-services.json` and `GoogleService-Info.plist` (or use FlutterFire CLI).

5. **Run the app:**
   ```bash
   flutter run
   ```

## 🛡️ Security
Sensitive API keys are managed using `flutter_dotenv` and are excluded from version control via `.gitignore`.

## 🧰 Tech Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage)
- **AI**: Google Gemini API
- **State Management**: Streams & RxDart
