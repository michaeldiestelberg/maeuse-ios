import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onDismiss: (Bool) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()
            FloatingCheeseHole(size: 120, duration: 9, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: -185, y: -410)
            FloatingCheeseHole(size: 70, duration: 7, delay: 1, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: 205, y: -260)
            FloatingCheeseHole(size: 40, duration: 8, delay: 2, fill: onboardingHole, stroke: Color.maeusCardBorder).offset(x: -210, y: 255)
            VStack(spacing: 14) {
                Spacer(minLength: 28)
                MouseCoin(size: 92, fill: logoCoinFill, shadow: colorScheme == .dark ? 0 : 6) {
                    Text("€").font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusInk)
                }
                .scaleEffect(appeared ? 1 : 0.82).opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                Text("Mäuse").font(.system(size: 44, weight: .heavy, design: .rounded)).tracking(-1.5)
                Text(loc("SplitSubtitle")).font(.system(size: 15, weight: .bold, design: .rounded)).multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    step(1, loc("LogExpenseTitle"), loc("LogExpenseDesc"), delay: 0.1)
                    step(2, loc("ChooseSplitTitle"), loc("ChooseSplitDesc"), delay: 0.22)
                    step(3, loc("TrackTotalsTitle"), loc("TrackTotalsDesc"), delay: 0.34)
                }.padding(.top, 8)
                Spacer(minLength: 12)
                Button(loc("GetStarted")) {
                    onDismiss(true)
                    withAnimation(.easeOut(duration: 0.3)) { isPresented = false }
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ctaForeground).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    ZStack { shape.fill(ctaShadow).offset(x: 4, y: 4); shape.fill(ctaBackground) }
                }
                Text(loc("SlangHint")).font(.system(size: 12, weight: .bold, design: .rounded)).italic().multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.maeusForeground).padding(.horizontal, 32).padding(.bottom, 28)
        }
        .fontDesign(.rounded)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.6, dampingFraction: 0.62)) { appeared = true }
        }
    }

    private func step(_ number: Int, _ title: String, _ subtitle: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.system(size: 14, weight: .heavy, design: .rounded)).frame(width: 30, height: 30)
                .foregroundStyle(Color.maeusInk)
                .background(Color.maeusCheese, in: Circle()).overlay(Circle().stroke(Color.maeusInk, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(subtitle).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color.maeusTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack { shape.fill(Color.maeusInk).offset(x: 3, y: 3); shape.fill(onboardingCard); shape.stroke(Color.maeusCardBorder, lineWidth: 2.5) }
        }
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.5).delay(delay), value: appeared)
    }

    private var onboardingBackground: Color { colorScheme == .dark ? Color(hex: "211A09") : .maeusCheese }
    private var onboardingHole: Color { colorScheme == .dark ? Color(hex: "2B2210") : Color(hex: "FFF6DE") }
    private var onboardingCard: Color { colorScheme == .dark ? Color(hex: "31280F") : Color(hex: "FFF6DE") }
    private var logoCoinFill: Color { colorScheme == .dark ? .maeusCheese : .white }
    private var ctaBackground: Color { colorScheme == .dark ? .maeusCheese : .maeusInk }
    private var ctaForeground: Color { colorScheme == .dark ? .maeusInk : .maeusCheese }
    private var ctaShadow: Color { colorScheme == .dark ? .black : Color.maeusInk.opacity(0.3) }
}
