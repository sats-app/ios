import SwiftUI

// MARK: - App Theme
struct AppTheme {
    static let shared = AppTheme()
    
    // Colors
    let primary = Color.orange
    let secondary = Color.gray
    let background = Color.white
    let surface = Color.gray.opacity(0.1)
    let onPrimary = Color.white
    let onSecondary = Color.black
    let onBackground = Color.black
    let onSurface = Color.black
    let accent = Color.orange
}

// MARK: - Color Extensions
extension Color {
    static let theme = AppTheme.shared
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.theme.primary)
            .foregroundColor(Color.theme.onPrimary)
            .cornerRadius(12)
            .font(.headline)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.theme.surface)
            .foregroundColor(Color.theme.onSurface)
            .cornerRadius(12)
            .font(.headline)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 50, height: 50)
            .background(Color.theme.surface)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct CircularButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 50, height: 50)
            .background(
                Circle()
                    .fill(isSelected ? Color.theme.primary : Color.theme.surface)
            )
            .foregroundColor(isSelected ? Color.theme.onPrimary : Color.theme.onSurface)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct NumberPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(Color.theme.onBackground)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.clear)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Text Styles
extension Text {
    func amountStyle() -> some View {
        self.font(.system(size: 48, weight: .light))
            .foregroundColor(Color.theme.onBackground)
    }
    
    func titleStyle() -> some View {
        self.font(.title2)
            .bold()
            .foregroundColor(Color.theme.onBackground)
    }
    
    func sectionHeaderStyle() -> some View {
        self.font(.headline)
            .fontWeight(.medium)
            .foregroundColor(Color.theme.onBackground)
    }
    
    func bodyStyle() -> some View {
        self.font(.subheadline)
            .foregroundColor(Color.theme.onBackground)
    }
    
    func captionStyle() -> some View {
        self.font(.caption)
            .foregroundColor(Color.theme.secondary)
    }
    
    func balanceStyle() -> some View {
        self.font(.headline)
            .fontWeight(.medium)
            .foregroundColor(Color.theme.onBackground)
    }
}

// MARK: - Custom Components
struct ThemedCheckbox: View {
    @Binding var isChecked: Bool
    let label: String
    
    var body: some View {
        HStack {
            Button(action: {
                isChecked.toggle()
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? Color.theme.primary : Color.theme.secondary)
            }
            
            Text(label)
                .bodyStyle()
            
            Spacer()
        }
    }
}

struct ThemedMemoField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memo")
                .sectionHeaderStyle()
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.theme.secondary.opacity(0.3), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.theme.background))
                    .frame(height: 80)
                
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color.theme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                
                TextField("", text: $text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(height: 80, alignment: .topLeading)
            }
        }
    }
}

struct ThemedIconButton: View {
    let iconName: String
    let action: () -> Void
    let tintColor: Color
    
    init(iconName: String, tintColor: Color = Color.theme.onBackground, action: @escaping () -> Void) {
        self.iconName = iconName
        self.tintColor = tintColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .foregroundColor(tintColor)
        }
    }
}

// MARK: - Button Extensions
extension Button {
    func primaryButtonStyle() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func compactButtonStyle() -> some View {
        self.buttonStyle(CompactButtonStyle())
    }
    
    func circularButtonStyle(isSelected: Bool = false) -> some View {
        self.buttonStyle(CircularButtonStyle(isSelected: isSelected))
    }
    
    func numberPadButtonStyle() -> some View {
        self.buttonStyle(NumberPadButtonStyle())
    }
}