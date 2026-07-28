import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.open.heart.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text("Letters to My")
                .font(.largeTitle.bold())

            ProgressView()
                .controlSize(.regular)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
