import SwiftUI
import PhotosUI
import UIKit

struct RecipePhotoTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            RecipePhotoTransfer(data: data)
        }
    }
}

/// Pick or take a photo, then parse it into the shared import preview.
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scrapedRecipe: ScrapedRecipe?
    var initialImageData: Data?
    var onPaste: () -> Void
    var onManual: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var missingKey = !KeychainManager.hasGeminiAPIKey()
    @State private var parseTask: Task<Void, Never>?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if missingKey {
                        missingKeyCard
                    } else {
                        pickers
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay {
            if isParsing {
                parsingOverlay
            }
        }
        .onAppear {
            missingKey = !KeychainManager.hasGeminiAPIKey()
            if let initialImageData, !missingKey {
                beginParse(data: initialImageData)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                // Clear so picking the same photo again still triggers a retry.
                photoItem = nil
                if let transfer = try? await item.loadTransferable(type: RecipePhotoTransfer.self) {
                    beginParse(data: transfer.data)
                } else {
                    errorMessage = "Couldn't load that photo. Try another one."
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                beginParse(data: data)
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Button(action: {
                cancelParse()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("PHOTO")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .tracking(-0.5)

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private var pickers: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                rowLabel("Choose photo", icon: "photo")
            }
            .buttonStyle(.plain)

            if cameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    rowLabel("Take photo", icon: "camera")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.system(size: 16, weight: .regular, design: .serif))
            Spacer()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .boldShadow(Color.terra300, size: 3, radius: 16)
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GeminiError.noAPIKey.localizedDescription)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(.black)

            Button(action: onPaste) {
                Text("Paste text")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.terra500)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button(action: onManual) {
                Text("Manual")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .boldShadow(Color.terra500, size: 4, radius: 18)
    }

    private var parsingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Color.terra500)
                Text("Reading recipe")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.black)
                Button("Cancel") { cancelParse() }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.terra500)
            }
            .padding(24)
            .background(Color.bgBase)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
    }

    private func beginParse(data: Data) {
        guard !isParsing else { return }
        guard KeychainManager.hasGeminiAPIKey() else {
            missingKey = true
            return
        }
        guard let image = UIImage(data: data) else {
            errorMessage = "Couldn't read that photo."
            return
        }
        isParsing = true
        errorMessage = nil
        parseTask = Task { @MainActor in
            defer {
                isParsing = false
                parseTask = nil
            }
            do {
                let recipe = try await GeminiService.shared.parseRecipeFromImage(image)
                try Task.checkCancellation()
                scrapedRecipe = recipe
                dismiss()
            } catch is CancellationError {
                // Cancelled by the user; nothing to show.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func cancelParse() {
        parseTask?.cancel()
        parseTask = nil
        isParsing = false
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void

        init(onImage: @escaping (Data) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let data = image?.jpegData(compressionQuality: 0.85)
            picker.dismiss(animated: true) {
                if let data {
                    self.onImage(data)
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
