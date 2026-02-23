import SwiftUI
import PhotosUI

/// Allows users to pick a profile avatar from presets or upload a custom photo.
/// Stores the selection in `profileImageURL`:
/// - Presets: stored as "preset:emoji_name" (e.g., "preset:driver", "preset:chef")
/// - Custom photos: stored as the local file path
struct ProfileAvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profileImageURL: String

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var loadedImage: UIImage?
    @State private var isLoadingPhoto = false

    // Organized preset categories
    private let presetCategories: [(title: String, presets: [(id: String, emoji: String, label: String)])] = [
        ("Gig Worker", [
            ("driver", "\u{1F697}", "Driver"),
            ("delivery", "\u{1F6F5}", "Delivery"),
            ("chef", "\u{1F468}\u{200D}\u{1F373}", "Chef"),
            ("shopper", "\u{1F6D2}", "Shopper"),
            ("freelancer", "\u{1F4BB}", "Freelancer"),
            ("handyman", "\u{1F528}", "Handyman"),
        ]),
        ("Personality", [
            ("rocket", "\u{1F680}", "Rocket"),
            ("star", "\u{2B50}", "Star"),
            ("fire", "\u{1F525}", "Fire"),
            ("crown", "\u{1F451}", "Crown"),
            ("gem", "\u{1F48E}", "Gem"),
            ("lightning", "\u{26A1}", "Lightning"),
        ]),
        ("Animals", [
            ("fox", "\u{1F98A}", "Fox"),
            ("eagle", "\u{1F985}", "Eagle"),
            ("wolf", "\u{1F43A}", "Wolf"),
            ("lion", "\u{1F981}", "Lion"),
            ("owl", "\u{1F989}", "Owl"),
            ("bear", "\u{1F43B}", "Bear"),
        ]),
    ]

    private var avatarStatusLabel: String {
        if profileImageURL.isEmpty {
            return "No avatar selected"
        } else if profileImageURL.contains("googleusercontent") {
            return "From your Google account"
        } else if profileImageURL.contains("apple") {
            return "From your Apple account"
        } else if profileImageURL.hasPrefix("https://") || profileImageURL.hasPrefix("http://") {
            return "Synced from your account"
        } else if profileImageURL.hasPrefix("preset:") {
            return "Preset avatar"
        } else {
            return "Custom photo"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Current avatar preview
                currentAvatarPreview

                // Upload photo option
                photoUploadSection

                // Preset categories
                ForEach(presetCategories, id: \.title) { category in
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(category.title)
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3), spacing: Spacing.md) {
                            ForEach(category.presets, id: \.id) { preset in
                                presetButton(preset)
                            }
                        }
                    }
                }

                // Remove avatar option
                if !profileImageURL.isEmpty {
                    Button {
                        profileImageURL = ""
                        HapticManager.shared.tap()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                            Text("Remove Avatar")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(BrandColors.destructive)
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .padding(Spacing.lg)
        }
        .background(BrandColors.groupedBackground)
        .navigationTitle("Choose Avatar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(from: newItem)
        }
    }

    // MARK: - Current Avatar Preview

    private var currentAvatarPreview: some View {
        VStack(spacing: Spacing.md) {
            ProfileAvatarView(
                profileImageURL: profileImageURL,
                initials: "ME",
                size: 96
            )

            Text(avatarStatusLabel)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textTertiary)
        }
    }

    // MARK: - Photo Upload

    private var photoUploadSection: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(BrandColors.primary.opacity(0.1))
                        .frame(width: 44, height: 44)

                    if isLoadingPhoto {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(BrandColors.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload Photo")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text("Choose from your photo library")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .padding(Spacing.md)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
        }
    }

    // MARK: - Preset Button

    private func presetButton(_ preset: (id: String, emoji: String, label: String)) -> some View {
        let isSelected = profileImageURL == "preset:\(preset.id)"

        return Button {
            profileImageURL = "preset:\(preset.id)"
            HapticManager.shared.select()
        } label: {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? BrandColors.primary.opacity(0.15) : BrandColors.cardBackground)
                        .frame(width: 64, height: 64)

                    if isSelected {
                        Circle()
                            .stroke(BrandColors.primary, lineWidth: 2.5)
                            .frame(width: 64, height: 64)
                    }

                    Text(preset.emoji)
                        .font(.system(size: 32))
                }

                Text(preset.label)
                    .font(Typography.caption2)
                    .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
            }
        }
        .buttonStyle(GWButtonPressStyle())
    }

    // MARK: - Photo Loading

    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }

            // Resize to reasonable avatar size (200x200)
            let resized = resizeImage(image, targetSize: CGSize(width: 400, height: 400))

            // Save to app documents
            guard let jpegData = resized.jpegData(compressionQuality: 0.8) else { return }

            let fileName = "avatar_\(UUID().uuidString.prefix(8)).jpg"
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent(fileName)

            do {
                // Remove old custom avatar if exists
                if profileImageURL.hasPrefix("/") || profileImageURL.contains("avatar_") {
                    let oldURL = documentsURL.appendingPathComponent(
                        (profileImageURL as NSString).lastPathComponent
                    )
                    try? FileManager.default.removeItem(at: oldURL)
                }

                try jpegData.write(to: fileURL)
                profileImageURL = fileURL.path
                HapticManager.shared.success()
            } catch {
                #if DEBUG
                print("Failed to save avatar: \(error)")
                #endif
            }
        }
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Reusable Avatar Display Component

/// Displays a profile avatar from either a preset, custom photo, or initials fallback.
/// Use this anywhere you need to show the user's avatar.
struct ProfileAvatarView: View {
    let profileImageURL: String
    let initials: String
    var size: CGFloat = 52

    // Organized preset lookup
    private static let presetEmojis: [String: String] = [
        "driver": "\u{1F697}", "delivery": "\u{1F6F5}", "chef": "\u{1F468}\u{200D}\u{1F373}",
        "shopper": "\u{1F6D2}", "freelancer": "\u{1F4BB}", "handyman": "\u{1F528}",
        "rocket": "\u{1F680}", "star": "\u{2B50}", "fire": "\u{1F525}",
        "crown": "\u{1F451}", "gem": "\u{1F48E}", "lightning": "\u{26A1}",
        "fox": "\u{1F98A}", "eagle": "\u{1F985}", "wolf": "\u{1F43A}",
        "lion": "\u{1F981}", "owl": "\u{1F989}", "bear": "\u{1F43B}",
    ]

    /// Whether the URL is a remote (http/https) URL — e.g. Google or Apple profile photo
    private var isRemoteURL: Bool {
        profileImageURL.hasPrefix("http://") || profileImageURL.hasPrefix("https://")
    }

    var body: some View {
        ZStack {
            if profileImageURL.hasPrefix("preset:") {
                // Preset emoji avatar
                let presetId = String(profileImageURL.dropFirst(7))
                let emoji = Self.presetEmojis[presetId] ?? "\u{1F464}"

                Circle()
                    .fill(BrandColors.primary.opacity(0.12))
                    .frame(width: size, height: size)

                Text(emoji)
                    .font(.system(size: size * 0.45))
            } else if isRemoteURL, let url = URL(string: profileImageURL) {
                // Remote photo (Google, Apple profile pics)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure:
                        initialsFallback
                    case .empty:
                        Circle()
                            .fill(BrandColors.primary.opacity(0.08))
                            .frame(width: size, height: size)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(size > 60 ? 0.8 : 0.5)
                            }
                    @unknown default:
                        initialsFallback
                    }
                }
            } else if !profileImageURL.isEmpty, let image = loadLocalImage() {
                // Custom photo from local file
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Initials fallback
                initialsFallback
            }
        }
        .frame(width: size, height: size)
    }

    private var initialsFallback: some View {
        ZStack {
            Circle()
                .fill(BrandColors.primary.opacity(0.12))
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColors.primary)
        }
    }

    private func loadLocalImage() -> UIImage? {
        // Try as absolute path first, then relative to documents
        if FileManager.default.fileExists(atPath: profileImageURL) {
            return UIImage(contentsOfFile: profileImageURL)
        }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent((profileImageURL as NSString).lastPathComponent)
        return UIImage(contentsOfFile: fileURL.path)
    }
}
