import SwiftUI

struct ProfileMenuSheet: View {
    var onSharingTapped: () -> Void
    var onCalendarTapped: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Account")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.cardWhite)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            VStack(spacing: 16) {
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onSharingTapped()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(HomeQuiet.ink)
                        Text("Sharing")
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                    .padding(20)
                    .homeQuietCard()
                }
                
                if let onCalendarTapped = onCalendarTapped {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onCalendarTapped()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(HomeQuiet.ink)
                            Text("Calendar")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(HomeQuiet.quiet)
                        }
                        .padding(20)
                        .homeQuietCard()
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(Color.bgBase.ignoresSafeArea())
    }
}
