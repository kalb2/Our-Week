//
//  AISettingsView.swift
//  OurWeek
//
//  Settings screen for managing Gemini AI features.
//

import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var hasAPIKey = KeychainManager.hasGeminiAPIKey()
    @State private var showAPIKey = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showDeleteConfirm = false

    private let rateLimiter = RateLimiter.shared

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // API Key Section
                    apiKeySection

                    // Test Connection
                    if hasAPIKey {
                        testConnectionSection
                    }

                    // Usage Section
                    if hasAPIKey {
                        usageSection
                    }

                    // Cache Section
                    if hasAPIKey {
                        cacheSection
                    }

                    // Info Section
                    infoSection

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .background(Color.bgBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 68, height: 68)
                    .offset(x: 3, y: 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.lilac500, Color.sky500],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2.5))

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("AI FEATURES")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(-0.5)

            Text("POWERED BY GOOGLE GEMINI")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lilac500)
                .tracking(1.5)
        }
        .padding(.top, 16)
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.terra500)
                Text("API KEY")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            // Status
            HStack(spacing: 8) {
                if hasAPIKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.lime500)
                    Text("API Key Saved")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.lime500)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No API Key")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            // Input field
            if !hasAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Paste your Gemini API key", text: $apiKeyInput)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                        .boldShadow(.black, size: 3, radius: 14)

                    HStack(spacing: 12) {
                        Button(action: saveAPIKey) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                Text("SAVE KEY")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .tracking(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: apiKeyInput.isEmpty ? [.gray] : [Color.lime500, Color.lime400],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(action: {
                            if let url = URL(string: "https://ai.google.dev/") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                                Text("GET FREE KEY")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .tracking(1)
                            }
                            .foregroundStyle(Color.sky500)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.sky100)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sky200, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Delete key button
                Button(action: { showDeleteConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                        Text("REMOVE KEY")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(1)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .alert("Remove API Key?", isPresented: $showDeleteConfirm) {
                    Button("Remove", role: .destructive) { deleteAPIKey() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll need to re-enter your key to use AI features.")
                }
            }
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
        .boldShadow(.black, size: 3, radius: 16)
    }

    // MARK: - Test Connection

    private var testConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sky500)
                Text("CONNECTION")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            Button(action: testConnection) {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(isTesting ? "TESTING..." : "TEST AI CONNECTION")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.sky500, Color.lilac500],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(isTesting)

            if let result = testResult {
                HStack(spacing: 8) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.lime500)
                        Text("Connection successful!")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.lime500)
                    case .failure(let message):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1.5))
    }

    // MARK: - Usage Section

    private var usageSection: some View {
        let remaining = rateLimiter.getRemainingRequests()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.terra500)
                Text("USAGE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            // Daily usage
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                    Spacer()
                    Text("\(rateLimiter.dailyCount) / \(RateLimiter.dailyLimit)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.terra400, Color.peach500],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geo.size.width * CGFloat(rateLimiter.dailyCount) / CGFloat(RateLimiter.dailyLimit),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                Text("Resets in \(rateLimiter.dailyResetFormatted)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
            }

            Divider()

            // Per-minute usage
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per Minute")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                    Text("Free tier limits")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }
                Spacer()
                Text("\(remaining.perMinute) left")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(remaining.perMinute > 5 ? Color.lime500 : .orange)
            }

            // Total all-time
            HStack {
                Text("All-time requests")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(rateLimiter.totalCount)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.lilac500)
            }

            Divider()

            Button(action: {
                rateLimiter.resetAllLimits()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text("RESET COUNTERS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(0.5)
                }
                .foregroundStyle(Color.sky500)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.sky100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.sky200, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1.5))
    }

    // MARK: - Cache Section

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.sky500)
                Text("CACHE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            HStack {
                Text("\(AIResponseCache.shared.cachedItemCount) items cached")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                Spacer()

                Button(action: {
                    AIResponseCache.shared.clearCache()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold))
                        Text("CLEAR")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color.terra500)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.terra100)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1.5))
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.gray)
                Text("ABOUT")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "sparkles", text: "Generate food photos for recipes")
                infoRow(icon: "doc.text", text: "AI-powered recipe parsing from URLs")
                infoRow(icon: "dollarsign.circle", text: "100% free — no credit card needed")
                infoRow(icon: "lock.shield", text: "API key stored securely in Keychain")
            }

            Text("Free tier: 1,500 requests/day • 15 requests/min")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1.5))
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.lilac500)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try KeychainManager.saveGeminiAPIKey(trimmed)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                hasAPIKey = true
                apiKeyInput = ""
                testResult = nil
            }
        } catch {
            testResult = .failure("Could not save API key")
        }
    }

    private func deleteAPIKey() {
        try? KeychainManager.deleteGeminiAPIKey()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            hasAPIKey = false
            testResult = nil
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let success = try await GeminiService.shared.testConnection()
                await MainActor.run {
                    withAnimation {
                        isTesting = false
                        testResult = success ? .success : .failure("No response received")
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        isTesting = false
                        testResult = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }
}
