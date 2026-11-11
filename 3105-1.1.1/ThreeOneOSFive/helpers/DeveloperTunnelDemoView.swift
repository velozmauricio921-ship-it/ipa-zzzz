import SwiftUI

private enum DemoTunnelPhase {
    case idle
    case discovering
    case confirming
    case ready

    var title: String {
        switch self {
        case .idle: return "Sin conexion"
        case .discovering: return "Buscando (demo)"
        case .confirming: return "Confirmando (demo)"
        case .ready: return "Listo (simulado)"
        }
    }

    var detail: String {
        switch self {
        case .idle: return "No hay ningun dispositivo conectado."
        case .discovering: return "Mostrando el paso de busqueda, sin escanear dispositivos."
        case .confirming: return "Representando una confirmacion ficticia."
        case .ready: return "La secuencia visual termino; no se creo un tunel real."
        }
    }

    var tint: Color {
        switch self {
        case .idle: return DemoPalette.muted
        case .discovering, .confirming: return DemoPalette.blue
        case .ready: return DemoPalette.green
        }
    }
}

private enum DemoPalette {
    static let paper = Color(red: 0.95, green: 0.95, blue: 0.91)
    static let surface = Color(red: 1.0, green: 1.0, blue: 0.98)
    static let ink = Color(red: 0.11, green: 0.16, blue: 0.14)
    static let muted = Color(red: 0.46, green: 0.51, blue: 0.48)
    static let forest = Color(red: 0.09, green: 0.23, blue: 0.20)
    static let lime = Color(red: 0.83, green: 0.94, blue: 0.42)
    static let blue = Color(red: 0.28, green: 0.45, blue: 0.84)
    static let green = Color(red: 0.34, green: 0.57, blue: 0.29)
    static let line = Color(red: 0.86, green: 0.88, blue: 0.84)
}

private struct DemoTunnelEvent: Identifiable {
    let id = UUID()
    let time = Date()
    let message: String
}

struct DeveloperTunnelDemoView: View {
    @State private var phase: DemoTunnelPhase = .idle
    @State private var events = [
        DemoTunnelEvent(message: "Vista de demostracion iniciada.")
    ]
    @State private var simulationTask: Task<Void, Never>?

    private var isRunning: Bool {
        phase == .discovering || phase == .confirming
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusPanel
                    devicePanel
                    actionButton
                    safetyNote
                    activityPanel
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(DemoPalette.paper.ignoresSafeArea())
            .navigationTitle("Developer Tunnel")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(DemoPalette.forest)
        .onDisappear {
            if isRunning {
                stopSimulation()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("LOCAL STUDY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DemoPalette.muted)

                Text("SIMULACION")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DemoPalette.lime, in: Capsule())
                    .foregroundStyle(DemoPalette.forest)
            }

            Text("Developer connection")
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(DemoPalette.ink)

            Text("Una vista de estudio del flujo de conexion, sin emparejar ni acceder a un iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(DemoPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phase == .ready ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(phase.tint)
                    .frame(width: 40, height: 40)
                    .background(phase.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DemoPalette.ink)
                    Text(phase.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(DemoPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if isRunning {
                ProgressView(value: phase == .discovering ? 0.35 : 0.72)
                    .tint(DemoPalette.blue)
            }
        }
        .padding(16)
        .background(DemoPalette.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DemoPalette.line, lineWidth: 1))
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("DISPOSITIVO DE EJEMPLO")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(DemoPalette.muted)

            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 21))
                    .foregroundStyle(DemoPalette.forest)
                    .frame(width: 42, height: 42)
                    .background(DemoPalette.paper, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("iPhone de muestra")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DemoPalette.ink)
                    Text("SIM-0001 · Identidad inventada")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DemoPalette.muted)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(phase == .ready ? DemoPalette.green : DemoPalette.muted.opacity(0.45))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(phase == .ready ? "Estado simulado listo" : "Sin conexion real")
            }

            Divider().overlay(DemoPalette.line)

            Label("Metodo: simulacion local", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 11))
                .foregroundStyle(DemoPalette.muted)
        }
        .padding(16)
        .background(DemoPalette.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DemoPalette.line, lineWidth: 1))
    }

    private var actionButton: some View {
        Button {
            if isRunning {
                stopSimulation()
            } else {
                startSimulation()
            }
        } label: {
            HStack(spacing: 8) {
                if isRunning {
                    Image(systemName: "xmark")
                    Text("Cancelar simulacion")
                } else {
                    Image(systemName: phase == .ready ? "arrow.clockwise" : "play.fill")
                    Text(phase == .ready ? "Repetir simulacion" : "Simular flujo")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundStyle(.white)
            .background(DemoPalette.forest, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Solo cambia estados visuales locales; no inicia una conexion.")
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(DemoPalette.blue)
            Text("No usa Remote Pairing, RSD, USB, Wi-Fi ni servicios privados de Apple. Ningun dispositivo se conecta realmente.")
                .font(.system(size: 11))
                .foregroundStyle(DemoPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DemoPalette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Actividad local")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(DemoPalette.ink)
                Spacer()
                Text("VOLATIL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(DemoPalette.muted)
            }

            ForEach(events.prefix(5)) { event in
                HStack(alignment: .top, spacing: 10) {
                    Text(event.time, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DemoPalette.muted)
                    Text(event.message)
                        .font(.system(size: 11))
                        .foregroundStyle(DemoPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(DemoPalette.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DemoPalette.line, lineWidth: 1))
    }

    private func startSimulation() {
        simulationTask?.cancel()
        phase = .discovering
        addEvent("Inicio de busqueda simulada; no se escanearon dispositivos.")

        simulationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            phase = .confirming
            addEvent("Paso de confirmacion mostrado; no se solicito confianza al usuario.")

            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            phase = .ready
            simulationTask = nil
            addEvent("Fin de la secuencia visual. No se creo ningun tunel.")
        }
    }

    private func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        phase = .idle
        addEvent("Simulacion cancelada.")
    }

    private func addEvent(_ message: String) {
        events.insert(DemoTunnelEvent(message: message), at: 0)
        events = Array(events.prefix(10))
    }
}

#if DEBUG
struct DeveloperTunnelDemoView_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperTunnelDemoView()
    }
}
#endif