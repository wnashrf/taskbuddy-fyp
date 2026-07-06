# TaskBuddy

TaskBuddy is an academically aligned, cloud-backed mobile application designed to streamline project coordination, workload transparency, and assignment breakdown for university student groups.

*🎓 **Final Year Project Case Study** — Developed in partial fulfillment of the Bachelor of Computer Science (Hons) program at Universiti Teknologi PETRONAS (UTP).*

---

## 🛠️ The Problem Statement & Research Context
In higher education, student group assignments frequently suffer from unequal contribution (free-riding), fragmented coordination across multiple mismatched communication apps, and unclear initial task distribution.

TaskBuddy solves this academic coordination gap by embedding automated, AI-assisted document parsing directly within a real-time collaborative workspace, allowing teams to align milestones with the academic calendar from day one.

---

## 🚀 System Architecture & Data Flow
The platform is designed around a modern client-cloud model, ensuring a lightweight mobile layout while delegating data mutations and background processing pipelines to scalable microservices.

```text
  [ Flutter Mobile Client ] 
             │
             ├── (FlutterFire SDK / Real-time Listeners) ──> [ Cloud Firestore ]
             │
             └── (Assignment PDF Upload) ──────────────────> [ Firebase Cloud Storage ]
                                                                     │
                                                             (onFinalize Trigger)
                                                                     │
  [ Cloud Firestore ] <── (Save JSON Output) <── [ AI Module ] <── [ Cloud Functions ]
  ```
  
### Multilayered Structure
*   **Presentation Layer (Client):** High-performance UI engineered using Flutter (Dart) utilizing reactive Streams and RxDart for responsive state synchronization across group structures.
*   **Application Logic Layer:** Serverless JavaScript backend handlers validating transaction pipelines, operational queries, and tracking contribution logs.
*   **Backend & Data Layer:** Real-time data caching via Google Cloud Firestore, user identity handling via Firebase Authentication, and unstructured media processing via Cloud Storage.

---

## ⚡ Performance Metrics & Usability Validation
The framework was evaluated through internal benchmark simulations and an empirical usability testing study involving **30 university student participants**:

*   **Near-Instant Sync Speed:** State mutations propagate across all active group devices in **under 200 ms** via active Firestore snapshot loops.
*   **Efficient Interface Navigation:** **96.7%** of evaluated undergraduate participants rated the layout structure as intuitive and straightforward to interact with (Mean: 4.4/5.0).
*   **Accountability Optimization:** **96.7%** of users confirmed that the built-in transparency log metrics successfully enhanced individual contribution awareness.
*   **AI Pipeline Responsiveness:** Background text extraction and generative model responses completed end-to-end within **3 to 6 seconds**.

---

## 🧠 Core Features & Workflows

*   **AI Task Decomposition:** Automated analysis of uploaded assignment guidelines (PDF format) via backend microservices to extract primary milestones and present task recommendations to group leaders.
*   **Granular Accountability Logs:** Real-time logging of individual task status adjustments to build a centralized progress metric display, reducing free-riding friction.
*   **Academic Workload Mapping:** A calendar timeline module that links deadline objectives directly to university semester structures for structured tracking.
*   **Collaborative Team Workspaces:** Secure shared groups generated via unique join codes with distinct capability mappings between team leads and members.

---

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

---
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

---
## 🛡️ Security
Sensitive API keys are managed using `flutter_dotenv` and are excluded from version control via `.gitignore`.

---
## 🧰 Tech Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage)
- **AI**: Google Gemini API
- **State Management**: Streams & RxDart
