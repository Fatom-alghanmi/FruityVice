import SwiftUI
import PDFKit
import CoreLocation

// Store image + date/time + location + source info
struct FruitImageInfo {
    var image: UIImage
    var date: Date
    var location: CLLocation?
    var source: String // "Camera" or "Library"
}

struct ContentView: View {
    @State private var fruits: [Fruit] = []
    @State private var selectedFruit: Fruit? = nil

    // Store fruit images with extra info
    @State private var fruitImages: [String: FruitImageInfo] = [:]

    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @StateObject private var locationManager = LocationManager()

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationView {
            List(fruits) { fruit in
                Button(action: {
                    selectedFruit = fruit
                }) {
                    HStack {
                        Text(fruit.name)
                        Spacer()
                        if let info = fruitImages[fruit.name] {
                            Image(uiImage: info.image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .navigationTitle("Fruits")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save PDF") {
                        savePDFReport()
                    }
                }
            }
            .task {
                await loadFruits()
                loadSavedImages()
            }
            .sheet(item: $selectedFruit) { fruit in
                let binding = Binding<UIImage?>(
                    get: { fruitImages[fruit.name]?.image },
                    set: { newImage in
                        if let image = newImage {
                            let source = pickerSource == .camera ? "Camera" : "Library"
                            fruitImages[fruit.name] = FruitImageInfo(
                                image: image,
                                date: Date(),
                                location: locationManager.lastLocation,
                                source: source
                            )
                            saveImage(image, for: fruit.name)
                        } else {
                            fruitImages[fruit.name] = nil
                            deleteImage(for: fruit.name)
                        }
                    }
                )

                FlippableCardContainer(
                    fruit: fruit,
                    selectedImage: binding,
                    pickerSource: $pickerSource,
                    isCameraAvailable: isCameraAvailable
                )
                .id(fruit.id)
            }
        }
    }

    // MARK: - Fetch Fruits
    func loadFruits() async {
        guard let url = URL(string: "https://www.fruityvice.com/api/fruit/all") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([Fruit].self, from: data)
            DispatchQueue.main.async {
                fruits = decoded
            }
        } catch {
            print("Error loading fruits:", error)
        }
    }

    // MARK: - Image Persistence Helpers
    private func getImageURL(for fruitName: String) -> URL {
        let safeName = fruitName.replacingOccurrences(of: "/", with: "_")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("\(safeName).jpg")
    }

    private func saveImage(_ image: UIImage, for fruitName: String) {
        let url = getImageURL(for: fruitName)
        if let data = image.jpegData(compressionQuality: 0.9) {
            do {
                try data.write(to: url)
                print("✅ Saved image for \(fruitName) at \(url.path)")
            } catch {
                print("❌ Error saving image for \(fruitName):", error)
            }
        }
    }

    private func loadSavedImages() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "jpg" {
                let name = file.deletingPathExtension().lastPathComponent
                if let data = try? Data(contentsOf: file),
                   let image = UIImage(data: data) {
                    fruitImages[name] = FruitImageInfo(
                        image: image,
                        date: Date(),
                        location: nil,
                        source: "Unknown"
                    )
                }
            }
            print("✅ Loaded saved images: \(fruitImages.keys)")
        } catch {
            print("❌ Failed to load saved images:", error)
        }
    }

    private func deleteImage(for fruitName: String) {
        let url = getImageURL(for: fruitName)
        try? FileManager.default.removeItem(at: url)
        fruitImages[fruitName] = nil
        print("🗑️ Deleted image for \(fruitName)")
    }

    // MARK: - PDF Report with Date/Time & Location
    func savePDFReport() {
        let pdfMetaData = [
            kCGPDFContextCreator: "Fruity App",
            kCGPDFContextAuthor: "Your Name"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth = 612.0
        let pageHeight = 792.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            for fruit in fruits {
                guard let info = fruitImages[fruit.name] else { continue } // only include fruits with photos
                context.beginPage()

                let textAttributes = [
                    NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 20)
                ]

                var text = "\(fruit.name)\nFamily: \(fruit.family)\nCalories: \(fruit.nutritions.calories)"

                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                text += "\nPhoto Date: \(dateFormatter.string(from: info.date))"
                text += "\nSource: \(info.source)"

                if let location = info.location {
                    text += "\nLocation: Lat \(location.coordinate.latitude), Lon \(location.coordinate.longitude)"
                } else {
                    text += "\nLocation: Not available"
                }

                let textRect = CGRect(x: 20, y: 20, width: pageWidth - 40, height: 120)
                text.draw(in: textRect, withAttributes: textAttributes)

                // Draw image
                let image = info.image
                let imageMaxWidth = pageWidth - 40
                let imageMaxHeight = pageHeight - 150
                let aspectRatio = image.size.width / image.size.height
                var imageWidth = imageMaxWidth
                var imageHeight = imageWidth / aspectRatio
                if imageHeight > imageMaxHeight {
                    imageHeight = imageMaxHeight
                    imageWidth = imageHeight * aspectRatio
                }
                let imageRect = CGRect(
                    x: (pageWidth - imageWidth) / 2,
                    y: 140,
                    width: imageWidth,
                    height: imageHeight
                )
                image.draw(in: imageRect)
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FruitsReport.pdf")
        do {
            try data.write(to: tempURL)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Could not save PDF: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
