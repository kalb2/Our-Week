import SwiftUI
import UIKit
import CoreData

/// Full-screen cooking: one step at a time, large serif text, screen kept awake.
struct CookModeView: View {
    let recipe: Recipe
    /// Servings scale from the detail view, so the ingredient peek matches what he sees there.
    var servingMultiplier: Double = 1

    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var steps: [String] = []
    @State private var fallbackText = ""
    @State private var index = 0
    @State private var showIngredients = false
    @State private var wasIdleDisabled = false

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.88)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color.bgBase.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            load()
            wasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = wasIdleDisabled
        }
        .sheet(isPresented: $showIngredients) {
            ingredientsPeek
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close cook mode")
            Spacer()
            Text(progressText)
                .font(.system(size: 14))
                .foregroundStyle(HomeQuiet.quiet)
            Spacer()
            Button { showIngredients = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ingredients")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var progressText: String {
        steps.isEmpty ? (recipe.name ?? "Recipe") : "Step \(index + 1) of \(steps.count)"
    }

    @ViewBuilder
    private var content: some View {
        if !steps.isEmpty {
            ZStack {
                Text(steps[index])
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .id(index)
                    .transition(.opacity)
                // Tap the left third to go back, anywhere else to go on.
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle())
                        .frame(maxWidth: .infinity)
                        .onTapGesture { go(-1) }
                        .accessibilityHidden(true)
                    Color.clear.contentShape(Rectangle())
                        .frame(maxWidth: .infinity)
                        .onTapGesture { go(1) }
                        .accessibilityHidden(true)
                    Color.clear.contentShape(Rectangle())
                        .frame(maxWidth: .infinity)
                        .onTapGesture { go(1) }
                        .accessibilityHidden(true)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -40 { go(1) }
                    if value.translation.width > 40 { go(-1) }
                }
            )
        } else if !fallbackText.isEmpty {
            ScrollView {
                Text(fallbackText)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
            }
        } else {
            Text("This recipe has no steps yet.")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.quiet)
                .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if !steps.isEmpty && index > 0 {
                Button { go(-1) } label: {
                    Text("Back")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                if steps.isEmpty || index >= steps.count - 1 {
                    if !steps.isEmpty { dataManager.markCookedToday(recipe) }
                    dismiss()
                } else {
                    go(1)
                }
            } label: {
                Text(steps.isEmpty || index >= steps.count - 1 ? "Done" : "Next")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.terra500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var ingredientsPeek: some View {
        let ingredients = dataManager.sortedIngredients(for: recipe)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if ingredients.isEmpty {
                        Text(recipe.ingredients ?? "No ingredients listed.")
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                            .padding(.horizontal, 24)
                    }
                    ForEach(ingredients, id: \.objectID) { ing in
                        let fixed = RecipeScraperService.normalizedIngredient(
                            amount: ing.amount,
                            unit: ing.unit ?? "",
                            name: ing.name ?? "",
                            notes: ing.notes ?? ""
                        )
                        let amount = fixed.amount * servingMultiplier
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if amount > 0 {
                                Text(verbatim: CookingAmount.scaledLabel(amount, unit: fixed.unit))
                                    .foregroundStyle(Color.terra600)
                            }
                            Text(CountNoun.name(fixed.name, amount: amount, unit: fixed.unit))
                                .foregroundStyle(HomeQuiet.ink)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        Rectangle().fill(HomeQuiet.rule).frame(height: 1).padding(.horizontal, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func go(_ delta: Int) {
        guard !steps.isEmpty else { return }
        let next = index + delta
        guard steps.indices.contains(next) else { return }
        withAnimation(motion) { index = next }
    }

    private func load() {
        steps = dataManager.sortedInstructions(for: recipe)
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        fallbackText = (recipe.instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        index = 0
    }
}
