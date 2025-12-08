# Sensory Safari 🐢🐘🐒

**Sensory Safari** is an interactive, engaging cross-platform Flutter application designed as a learning companion. It combines gamified elements with sensory-friendly design to create an immersive experience.

## 🌟 Features

### 🔐 Authentication & User Management
- **Custom "Liquid Glass" UI**: A visually stunning login and signup interface featuring animated background blobs and glassmorphism effects.
- **Local User Management**: Supports creating unique user profiles stored in Cloud Firestore.
- **Secure Handling**: Users are authenticated anonymously via Firebase Auth while maintaining their profile data in Firestore.

### 🎮 Interactive "safari" Game Mode
- **Animal Companions**: Choose your guide from a selection of animated animals:
  - 🐢 Turtle
  - 🐱 Cat
  - 🐘 Elephant
  - 🐒 Monkey
- **Adaptive Difficulty Engine**:
  - **Standard Levels**: Easy (🙂), Medium (😐), Hard (😮‍💨), Very Hard (🤯).
  - **Adaptive Modes**: 🧠 Adaptive (adjusts to player performance) and ⚡️ Adaptive Fast.
- **Customizable Gameplay**:
  - **Tries**: Adjust the number of attempts (1–30).
  - **Stimulus Duration**: Control how long the stimulus is shown (1–10s).
  - **Outcome Duration**: Set the feedback duration (1–10s).
  - **Sensory Toggles**: Independent controls for **Lights** ☀️ and **Sound** 🔊.

### 🎨 Visual & Audio Experience
- **Dynamic Animations**: The UI feels alive with breathing animations, title pulsing, and mascot bobbing.
- **Haptic Feedback**: Integrated haptic responses for user interactions (e.g., selecting options, changing settings).
- **Responsive Design**: Optimized for different screen sizes with a layout that adapts from compact phones to tablets.

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **Backend**: [Firebase](https://firebase.google.com/)
  - **Firestore**: Database for user profiles and game settings.
  - **Authentication**: Anonymous auth for session management.
- **State Management**: `ChangeNotifier` / Provider pattern for app settings.
- **Persistence**: `shared_preferences` for local device settings (last logged-in user, basic configs).

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.5.3 or later)
- [CocoaPods](https://cocoapods.org/) (for iOS)
- Firebase Project configured.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kaushikvada3/Sensory_Safari_App.git
    cd sensory_safari_flutter
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    ```bash
    # For iOS Simulator
    open -a Simulator
    flutter run

    # For Web
    flutter run -d chrome
    ```

## ⚙️ Configuration

The app relies on `firebase_options.dart` for connection details. Ensure you have the correct Firebase configuration generated for your project using the FlutterFire CLI:

```bash
flutterfire configure
```

## 📱 Project Structure

- `lib/main.dart`: Entry point. Sets up Firebase and the main MaterialApp.
- `lib/startup/`: Contains the logic for the initial app flow:
    - `startup_gate_page.dart`: Manages the flow from Login -> Loading -> Rotate Gate.
    - `login_page.dart`: The main authentication screen.
- `lib/features/game/view/content_view.dart`: The core game dashboard where users select animals, difficulty, and settings.
- `lib/features/game/view/test_view.dart`: The actual gameplay view (referenced in routes).

## 🤝 Contributing

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---
*Built with ❤️ in Flutter*
