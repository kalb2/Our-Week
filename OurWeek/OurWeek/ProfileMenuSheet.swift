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
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.cardWhite)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
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
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.lilac500)
                        Text("Sharing Settings")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .padding(20)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
                    .boldShadow(Color.lilac400, size: 3, radius: 16)
                }
                
                if let onCalendarTapped = onCalendarTapped {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onCalendarTapped()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.terra500)
                            Text("Calendar Sync")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.gray)
                        }
                        .padding(20)
                        .background(Color.cardWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
                        .boldShadow(Color.terra400, size: 3, radius: 16)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(Color.bgBase.ignoresSafeArea())
    }
}
