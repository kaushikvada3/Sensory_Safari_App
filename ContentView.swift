//
//  ContentView.swift
//  SensorySafariNative
//
//  Created by Kaushik Vada on 6/13/25.
//


import SwiftUI
import UIKit
import Combine

// Global game pause/resume notifications for orientation guard
extension Notification.Name {
    static let gameShouldPause = Notification.Name("GameShouldPause")
    static let gameShouldResume = Notification.Name("GameShouldResume")
}

// MARK: - Kid-friendly controls
struct Preset { let name: String; let tries:Int; let stim:Int; let outcome:Int; let diff:Int }

struct StepperPill: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundColor(.white)
            HStack(spacing: 14) {
                Button { if value > range.lowerBound { value -= 1; tap() } } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 34, weight: .bold))
                }
                Text("\(value)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .frame(width: 72)
                Button { if value < range.upperBound { value += 1; tap() } } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 34, weight: .bold))
                }
            }
            .foregroundColor(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(radius: 6, y: 3)
    }
    private func tap() {
        let h1 = UIImpactFeedbackGenerator(style: .rigid); h1.prepare(); h1.impactOccurred()
    }
}

struct DifficultyCarousel: View {
    @Binding var selected: Int
    let levels: [(String, String, Color)] = [
        ("Easy", "🙂", .green),
        ("Medium", "😐", .orange),
        ("Hard", "😮‍💨", .red),
        ("Very Hard", "🤯", .purple)
    ]
    var tileWidth: CGFloat = 120
    var tileHeight: CGFloat = 84


    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                TabView(selection: $selected) {
                    ForEach(0..<levels.count, id: \.self) { i in
                        let delta = CGFloat(i - selected)
                        let (label, emoji, color) = levels[i]
                        VStack(spacing: 6) {
                            Text(emoji).font(.system(size: 44))
                            Text(label).font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(width: tileWidth, height: tileHeight)
                        .background(color.opacity(i == selected ? 0.95 : 0.7), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(i == selected ? 0.6 : 0.15), lineWidth: i == selected ? 3 : 1)
                        )
                        .scaleEffect(max(0.86, 1.0 - 0.09 * abs(delta)))
                        .rotation3DEffect(.degrees(Double(delta) * 24), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                        .opacity(Double(0.7 + (0.3 * (1 - min(1, abs(delta))))))
                        .tag(i)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
                    }
                }
                .frame(height: tileHeight + 14)
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .contentShape(Rectangle())
                // .onTapGesture removed
                .onChange(of: selected) { _ in
                    let g = UIImpactFeedbackGenerator(style: .rigid)
                    g.prepare(); g.impactOccurred()
                }

                // Chevron buttons (subtle pulse to suggest interaction)
                HStack {
                    Button {
                        if selected > 0 { selected -= 1 }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 2, y: 1)
                            .scaleEffect(1.0)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)

                    Spacer()

                    Button {
                        if selected < levels.count - 1 { selected += 1 }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 2, y: 1)
                            .scaleEffect(1.0)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<levels.count, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == selected ? 0.95 : 0.4))
                        .frame(width: i == selected ? 10 : 6, height: i == selected ? 10 : 6)
                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                        .scaleEffect(i == selected ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: selected)
                }
            }
        }
    }
}

struct IconToggle: View {
    let system: String; let label: String
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
            let g = UIImpactFeedbackGenerator(style: .rigid); g.prepare(); g.impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 30, weight: .bold))
                Text(label).font(.subheadline)
            }
            .foregroundColor(.white)
            .frame(width: 140, height: 84)
            .background((isOn ? Color.green : Color.gray.opacity(0.6)), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.15), lineWidth: 1))
            .shadow(radius: 6, y: 3)
        }.buttonStyle(.plain)
    }
}

// MARK: Shared ObservableObject for global state
class SensorySafariSettings: ObservableObject {
    @Published var selectedAnimal = 0
    @Published var selectedDifficulty = 0
    @Published var lightsOn = false
    @Published var soundOn = false
    @Published var numTries = 5.0
    @Published var stimDuration = 5.0
    @Published var outcomeDuration = 2.0
}

struct ContentView: View {
    @State private var titleVisible = false
    @State private var isPressed = false
    @State private var showCountdown = false
    @State private var breathe = false
    @State private var titleHue: Double = 0
    @State private var titlePulse: Bool = false
    @State private var titleWobble: Bool = false
    @State private var mascotBob: Bool = false
    
    // Orientation guard (pause game if device goes portrait)
    @State private var showRotateOverlay = false
    private let orientationNC = NotificationCenter.default

    // Orientation helper that prefers the window scene's interfaceOrientation
    struct OrientationUtils {
        static func interfaceOrientation() -> UIInterfaceOrientation? {
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
        }
        static func isLandscape() -> Bool {
            if let o = interfaceOrientation() { return o == .landscapeLeft || o == .landscapeRight }
            let s = UIScreen.main.bounds.size
            return s.width > s.height
        }
        static func isPortrait() -> Bool {
            if let o = interfaceOrientation() { return o == .portrait || o == .portraitUpsideDown }
            let s = UIScreen.main.bounds.size
            return s.height >= s.width
        }
    }

    // Debounce to avoid false triggers when rotating
    @State private var orientationDebounce: DispatchWorkItem? = nil
    
    @EnvironmentObject var settings: SensorySafariSettings
    @EnvironmentObject var router: AppRouter    // NEW for navigation
    
    let animals = ["turtle", "cat", "elephant", "monkey"]
    let difficulties = ["Easy", "Medium", "Hard", "Very Hard"]
    
    var body: some View {
        ZStack {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            GeometryReader { g in
                let compact = g.size.width < 930 || g.size.height < 380
                let colW: CGFloat = compact ? 190 : 220
                let hSpacing: CGFloat = compact ? 12 : 20
                let centerSpacing: CGFloat = compact ? 6 : 10
                let animalImg: CGFloat = compact ? 72 : 90
                let diffW: CGFloat = compact ? 104 : 120
                let diffH: CGFloat = compact ? 76 : 84
                
                HStack(alignment: .center, spacing: hSpacing) {
                    // Left controls
                    VStack {
                        VStack(spacing: 12) {
                            StepperPill(title: "Tries", value: .init(get: { Int(settings.numTries) }, set: { settings.numTries = Double($0) }), range: 1...10)
                            StepperPill(title: "Stimulus (sec)", value: .init(get: { Int(settings.stimDuration) }, set: { settings.stimDuration = Double($0) }), range: 1...10)
                            StepperPill(title: "Outcome (sec)", value: .init(get: { Int(settings.outcomeDuration) }, set: { settings.outcomeDuration = Double($0) }), range: 1...10)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .scaleEffect(compact ? 0.92 : 1.0)
                    }
                    .frame(width: colW)
                    .padding(.top, g.safeAreaInsets.top + (compact ? 6 : 10))
                    
                    // Center controls
                    VStack {
                        Spacer(minLength: g.safeAreaInsets.top + (compact ? 70 : 90))
                        
                        VStack(alignment: .center, spacing: centerSpacing) {
                            HStack(spacing: 8) {
                                Image(animals[settings.selectedAnimal])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                                    .offset(y: mascotBob ? -4 : 4)
                                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: mascotBob)
                                
                                Text("Sensory Safari")
                                    .font(.system(size: compact ? 32 : 36, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                                    .scaleEffect(titlePulse ? 1.04 : 1.0)
                                    .rotationEffect(.degrees(titleWobble ? 1.6 : -1.6))
                                    .opacity(titleVisible ? 1 : 0)
                            }
                            .padding(.top, 0)
                            .onAppear {
                                titleVisible = true
                                mascotBob = true
                                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                                    titlePulse.toggle()
                                }
                                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                                    titleWobble.toggle()
                                }
                            }
                            
                            // Animal selector
                            VStack(spacing: 0) {
                                Text("Animal")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.bottom, 0)
                                ZStack {
                                    TabView(selection: $settings.selectedAnimal) {
                                        ForEach(0..<animals.count, id: \.self) { i in
                                            Image(animals[i])
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: animalImg * 1.4, height: animalImg * 1.4)
                                                .tag(i)
                                        }
                                    }
                                    .frame(height: compact ? 140 : 168)
                                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .automatic))
                                    .animation(.easeInOut, value: settings.selectedAnimal)
                                    .onChange(of: settings.selectedAnimal) { _ in
                                        let g = UIImpactFeedbackGenerator(style: .medium)
                                        g.prepare(); g.impactOccurred()
                                    }
                                    .padding(.top, 0)

                                    HStack {
                                        Button {
                                            if settings.selectedAnimal > 0 { settings.selectedAnimal -= 1 }
                                        } label: {
                                            Image(systemName: "chevron.left.circle.fill")
                                                .font(.system(size: 28, weight: .bold))
                                                .foregroundColor(.white.opacity(0.9))
                                                .shadow(radius: 2, y: 1)
                                        }
                                        .buttonStyle(.plain)

                                        Spacer()

                                        Button {
                                            if settings.selectedAnimal < animals.count - 1 { settings.selectedAnimal += 1 }
                                        } label: {
                                            Image(systemName: "chevron.right.circle.fill")
                                                .font(.system(size: 28, weight: .bold))
                                                .foregroundColor(.white.opacity(0.9))
                                                .shadow(radius: 2, y: 1)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 4) // pull chevrons closer to the carousel
                                }
                            }
                            
                            // Difficulty selector
                            VStack(spacing: 0) {
                                Text("Difficulty Level").font(.title2).fontWeight(.bold)
                                DifficultyCarousel(selected: .init(
                                    get: { min(settings.selectedDifficulty, 3) },
                                    set: { settings.selectedDifficulty = $0 }
                                ), tileWidth: diffW, tileHeight: diffH)
                            }
                            
                            // Go button
                            Button {
                                isPressed = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isPressed = false
                                    showCountdown = true
                                }
                            } label: {
                                Text("GO!!!")
                                    .font(compact ? .title3 : .title)
                                    .bold()
                                    .padding(.horizontal, compact ? 70 : 90)
                                    .padding(.vertical, compact ? 10 : 12)
                                    .background(Color.green, in: Capsule())
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            }
                            .scaleEffect(isPressed ? 0.95 : (breathe ? 1.03 : 1.0))
                            .animation(.easeInOut(duration: 0.2), value: isPressed)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
                            .onAppear { breathe = true }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, g.safeAreaInsets.bottom + (compact ? 20 : 28))
                        
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Right toggles
                    VStack {
                        VStack(spacing: 12) {
                            IconToggle(system: "sun.max.fill", label: "Lights", isOn: $settings.lightsOn)
                            IconToggle(system: "speaker.wave.3.fill", label: "Sound", isOn: $settings.soundOn)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .scaleEffect(compact ? 0.92 : 1.0)
                    }
                    .padding(.top, g.safeAreaInsets.top + (compact ? 6 : 10))
                    .frame(width: colW)
                }
                .padding()
            }
            // Orientation Guard — pause when device rotates to portrait during gameplay
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(orientationNC.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Debounce minor bounces and rely on interfaceOrientation to avoid faceUp/unknown noise
                orientationDebounce?.cancel()
                let work = DispatchWorkItem {
                    let isLand = OrientationUtils.isLandscape()
                    let isPort = OrientationUtils.isPortrait()
                    if isPort {
                        if !showRotateOverlay {
                            showRotateOverlay = true
                            NotificationCenter.default.post(name: .gameShouldPause, object: nil)
                        }
                    } else if isLand {
                        if showRotateOverlay {
                            showRotateOverlay = false
                            NotificationCenter.default.post(name: .gameShouldResume, object: nil)
                        }
                    }
                }
                orientationDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            }
            .fullScreenCover(isPresented: $showCountdown) {
                CountdownView {
                    showCountdown = false
                    router.path.append(.test)  // NEW navigation
                }
            }
            // Blocks gameplay while device is portrait; auto-continues on landscape
            .fullScreenCover(isPresented: $showRotateOverlay) {
                OrientationLocked(mask: [.landscapeLeft, .landscapeRight]) {
                    RotateToLandscapeView {
                        // User rotated back to landscape — resume
                        showRotateOverlay = false
                        NotificationCenter.default.post(name: .gameShouldResume, object: nil)
                    }
                    .interactiveDismissDisabled(true)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 6)
            }
        }
    }
    
    struct SliderCard: View {
        var title: String
        @Binding var value: Double
        var range: ClosedRange<Double>
        var step: Double
        @State private var lastHapticTick: Int? = nil
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                HStack {
                    Text("\(Int(range.lowerBound))")
                        .font(.caption2)
                        .frame(width: 20)
                    Slider(value: $value, in: range, step: step)
                        .tint(.blue)
                        .onChange(of: value) { newVal in
                            let tick = Int(round(newVal))
                            if tick != lastHapticTick {
                                // Strong, crisp tick for each integer step
                                let rigid = UIImpactFeedbackGenerator(style: .rigid)
                                rigid.prepare()
                                rigid.impactOccurred()
                                
                                // Extra emphasis at bounds
                                let low = Int(range.lowerBound.rounded())
                                let high = Int(range.upperBound.rounded())
                                if tick == low || tick == high {
                                    let heavy = UIImpactFeedbackGenerator(style: .heavy)
                                    heavy.prepare()
                                    heavy.impactOccurred()
                                }
                                lastHapticTick = tick
                            }
                        }
                    Text("\(Int(range.upperBound))")
                        .font(.caption2)
                        .frame(width: 20)
                }
                Text("Selected: \(value, specifier: "%.1f")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(width: 200)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 3)
        }
    }
    
    struct ToggleCard: View {
        var title: String
        @Binding var isOn: Bool
        
        var body: some View {
            VStack {
                Toggle(isOn: $isOn) {
                    Text(title)
                        .font(.headline)
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
            }
            .padding()
            .frame(width: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 3)
        }
    }
    
    struct DifficultyCard: View {
        let label: String
        let index: Int
        @State private var hue: Double = 0.0
        
        var body: some View {
            ZStack {
                if index == 3 {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AngularGradient(
                            gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]),
                            center: .center,
                            angle: .degrees(hue)
                        ))
                        .onAppear {
                            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                                hue = 360
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorForIndex(index))
                }
                Text(label)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .frame(width: 160, height: 50)
            .shadow(radius: 3)
        }
        
        private func colorForIndex(_ idx: Int) -> Color {
            switch idx {
            case 0: return .green
            case 1: return .orange
            case 2: return .red
            default: return .clear
            }
        }
    }
    
    struct CountdownView: View {
        @Environment(\.dismiss) var dismiss
        @State private var counter = 3
        var completion: () -> Void
        
        var body: some View {
            ZStack {
                Color.black.opacity(0.7).ignoresSafeArea()
                if counter >= 0 {
                    Text("\(counter)")
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .scaleEffect(1.2)
                        .transition(.scale.combined(with: .opacity))
                        .id(counter)
                        .animation(.easeInOut(duration: 0.6), value: counter)
                }
            }
            .onAppear { startCountdown() }
        }
        
        func startCountdown() {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if counter > 0 {
                    counter -= 1
                } else {
                    timer.invalidate()
                    completion()
                }
            }
        }
    }
    
    } // End of ContentView struct

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SensorySafariSettings())
            .environmentObject(AppRouter())
    }
}
