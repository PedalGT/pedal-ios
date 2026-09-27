import SwiftUI
import PhotosUI

/// Take a photo of the bike before ending a ride. The check runs on device
/// (BikePhotoChecker). While Config.requireBikePhotoToEndRide is false the rider
/// can still end the ride without a passing photo.
struct BikePhotoCheckView: View {
    let bikeName: String?
    let expectedColor: String?
    /// nil = test mode from Settings: no ride to end.
    var onEndRide: ((BikePhotoResult?) async throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var photo: UIImage?
    @State private var result: BikePhotoResult?
    @State private var isChecking = false
    @State private var isEnding = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(onEndRide == nil
                         ? "Test the bike photo check. Take or choose a photo of a bike."
                         : "Take a photo of the whole bike to check its condition before you lock it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let expectedColor {
                        Label("\(bikeName ?? "This bike") is \(expectedColor)", systemImage: "paintpalette")
                            .font(.footnote.weight(.medium))
                    }

                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if isChecking {
                        ProgressView("Checking photo…")
                    } else if let result {
                        resultCard(result)
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }

                    photoButtons
                    endButtons
                }
                .padding(20)
            }
            .background(Theme.screen)
            .navigationTitle("Bike photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(onEndRide == nil ? "Done" : "Cancel") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { use(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        use(image)
                    } else {
                        errorMessage = "Couldn't open that photo. Try another one."
                    }
                    libraryItem = nil
                }
            }
        }
    }

    // MARK: - Pieces

    private var photoButtons: some View {
        VStack(spacing: 10) {
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label(photo == nil ? "Take photo" : "Take a new photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(onEndRide == nil || result?.passed != true ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
            }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .disabled(isChecking || isEnding)
    }

    @ViewBuilder
    private var endButtons: some View {
        if let onEndRide {
            VStack(spacing: 10) {
                if result?.passed == true {
                    Button { end(onEndRide, with: result) } label: {
                        LoadingLabel(title: "End ride and lock", isLoading: isEnding)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if !Config.requireBikePhotoToEndRide {
                    Button { end(onEndRide, with: result) } label: {
                        Text(result == nil ? "End ride without photo (testing)" : "End ride anyway (testing)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .font(.footnote)
                }
            }
            .disabled(isChecking || isEnding)
        }
    }

    private func resultCard(_ r: BikePhotoResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row(ok: r.bikeDetected, title: "Bike",
                value: r.bikeDetected ? "Found (\(Int(r.confidence * 100))%)" : "Not found")
            row(ok: r.colorMatches, title: "Color", value: colorText(r))
            row(ok: r.bikeDetected ? r.condition == "Good" || r.condition == "Fair" : nil,
                title: "Condition", value: r.condition)

            if !r.bikeDetected {
                Text("We couldn't see a bike. Take a new photo with the whole bike in the frame.")
                    .font(.footnote).foregroundStyle(.red)
            } else if r.colorMatches == false {
                Text("This doesn't look like \(bikeName ?? "the right bike"). It should be \(r.expectedColor ?? ""). Make sure you're photographing the bike you rode.")
                    .font(.footnote).foregroundStyle(.red)
            } else {
                Text("Looks good.").font(.footnote).foregroundStyle(Theme.bikeLane)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(ok: Bool?, title: String, value: String) -> some View {
        HStack {
            Image(systemName: ok == nil ? "minus.circle" : ok! ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok == nil ? Color.secondary : ok! ? Theme.bikeLane : Color.red)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func colorText(_ r: BikePhotoResult) -> String {
        guard let detected = r.detectedColor else { return "Unclear" }
        guard let expected = r.expectedColor else { return "\(detected.capitalized) (no color on file)" }
        return r.colorMatches == true ? detected.capitalized : "\(detected.capitalized), expected \(expected)"
    }

    // MARK: - Actions

    private func use(_ image: UIImage) {
        photo = image
        result = nil
        errorMessage = nil
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                result = try await BikePhotoChecker.check(image, expectedColor: expectedColor)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func end(_ onEndRide: @escaping (BikePhotoResult?) async throws -> Void, with result: BikePhotoResult?) {
        errorMessage = nil
        isEnding = true
        Task {
            defer { isEnding = false }
            do {
                try await onEndRide(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Lets the camera button switch between the two app button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// UIKit camera, since SwiftUI has no built-in one.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
