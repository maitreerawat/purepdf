import SwiftUI

#if os(iOS)
@main
struct PurePDFApp: App {
    @StateObject private var vault = PDFVaultStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(vault)
                .onOpenURL { url in
                    vault.importExternalPDF(from: url)
                }
        }
    }
}
#endif
