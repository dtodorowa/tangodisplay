import SwiftUI
import TangoDisplayCore

struct IdleView: View {
    let mode: DisplayMode
    @ObservedObject var settings: AppSettings
    let profile: AppearanceProfile

    var body: some View {
        ZStack {
            // Idle message
            if !settings.idleMessage.isEmpty {
                let split = profile.displayLayout == .textLeftImageRight
                Text(settings.idleMessage)
                    .font(profile.idleMessageFont)
                    .foregroundColor(profile.idleMessageSwiftUIColor)
                    .multilineTextAlignment(split ? .leading : .center)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: split ? .leading : .center)
                    .padding(.horizontal, split ? 44 : 0)
            }

            // Paused banner
            if mode == .paused {
                VStack {
                    HStack {
                        Text("PAUSED")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(20)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
