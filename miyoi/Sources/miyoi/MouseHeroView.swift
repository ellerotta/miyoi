import MiyoiKit
import RealityKit
import SwiftUI

private func usdzResourceName(for modelID: String) -> String {
    switch modelID {
    case "r6":
        return "r6"
    case "r5u", "m5u":
        return "r5u"
    default:
        return "r5u"
    }
}

struct MouseHeroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let modelID: String

    @State private var root = Entity()
    @State private var cameraEntity = PerspectiveCamera()

    var body: some View {
        RealityView { content in
            content.add(root)

            cameraEntity.camera.fieldOfViewInDegrees = 42
            let cameraAnchor = AnchorEntity(world: .zero)
            cameraAnchor.addChild(cameraEntity)
            content.add(cameraAnchor)

            let keyLight = DirectionalLight()
            keyLight.light.intensity = 3000
            keyLight.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0.3, 0))
            let lightAnchor = AnchorEntity(world: .zero)
            lightAnchor.addChild(keyLight)
            content.add(lightAnchor)

            await loadIfNeeded()
        } update: { _ in
            // RealityKit entities are configured during initial loading
        }
        .frame(width: 256, height: 256)
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadIfNeeded() async {
        let resourceName = usdzResourceName(for: modelID)

        do {
            guard let url = Bundle.module.url(forResource: resourceName, withExtension: "usdz") else {
                print("[MouseHeroView] ❌ usdz not found in bundle for resource name: \(resourceName)")
                print("[MouseHeroView] bundle path: \(Bundle.module.bundlePath)")
                return
            }
            print("[MouseHeroView] ✅ found usdz at: \(url.path)")

            let entity = try await Entity(contentsOf: url)
            entity.name = "mouseModel"
            print("[MouseHeroView] ✅ entity loaded, child count: \(entity.children.count)")

            let bounds = entity.visualBounds(relativeTo: nil)
            let extent = bounds.extents
            print("[MouseHeroView] bounds extents: \(extent), center: \(bounds.center)")
            let largest = max(extent.x, max(extent.y, extent.z))
            let targetSize: Float = 0.6
            let scale = largest > 0 ? targetSize / largest : 1

            let faceViewerRotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))

            entity.scale = SIMD3<Float>(repeating: scale)
            entity.orientation = faceViewerRotation
            entity.position = -(faceViewerRotation.act(bounds.center)) * scale
            print("[MouseHeroView] applied scale: \(scale), position: \(entity.position)")

            root.children.removeAll()
            root.addChild(entity)
            print("[MouseHeroView] ✅ entity added to root, root child count: \(root.children.count)")

            await playReveal()
        } catch {
            print("[MouseHeroView] ❌ failed to load entity: \(error)")
        }
    }

    /// three-stage camera move matching the sketch: start close-up looking almost
    /// straight down at the top panel (buttons/wheel), then pull back and tilt down
    /// to a 3/4 angle, then settle into the final side-on showcase shot
    @MainActor
    private func playReveal() async {
        guard root.children.first(where: { $0.name == "mouseModel" }) != nil else { return }

        let stage1Position = SIMD3<Float>(0, 0.55, 0.12)
        let stage1Look = lookAtRotation(from: stage1Position, to: .zero)

        let stage2Position = SIMD3<Float>(0, 0.42, 0.55)
        let stage2Look = lookAtRotation(from: stage2Position, to: .zero)

        let stage3Position = SIMD3<Float>(0, 0.22, 0.85)
        let stage3Look = lookAtRotation(from: stage3Position, to: SIMD3<Float>(0, 0.02, 0))

        if reduceMotion {
            cameraEntity.position = stage3Position
            cameraEntity.orientation = stage3Look
            return
        }

        cameraEntity.position = stage1Position
        cameraEntity.orientation = stage1Look
        print("[MouseHeroView] camera stage1 pos: \(stage1Position), forward test: \(stage1Look.act(SIMD3<Float>(0, 0, -1)))")

        var stage2Transform = cameraEntity.transform
        stage2Transform.translation = stage2Position
        stage2Transform.rotation = stage2Look

        var stage3Transform = cameraEntity.transform
        stage3Transform.translation = stage3Position
        stage3Transform.rotation = stage3Look

        do {
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            return
        }

        cameraEntity.move(to: stage2Transform, relativeTo: cameraEntity.parent, duration: 0.5, timingFunction: .easeInOut)

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }

        cameraEntity.move(to: stage3Transform, relativeTo: cameraEntity.parent, duration: 0.6, timingFunction: .easeInOut)
    }

    private func lookAtRotation(from eye: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let forward = normalize(target - eye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = cross(right, forward)
        let rotationMatrix = simd_float3x3(right, up, -forward)
        return simd_quatf(rotationMatrix)
    }
}

struct MouseRevealScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: DeviceModel
    let onFinished: () -> Void

    @State private var titleVisible = false

    var body: some View {
        VStack(spacing: 18) {
            MouseHeroView(modelID: model.id)
                .id(model.id)
                .shadow(color: .primary.opacity(0.12), radius: 24, y: 12)

            VStack(spacing: 4) {
                Text(model.name)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(titleVisible ? 1 : 0)
            .offset(y: titleVisible ? 0 : 8)
            .accessibilityHidden(!titleVisible)

            continueButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.8)) {
                titleVisible = true
            }
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        if #available(macOS 26.0, *) {
            Button("Continue", action: onFinished)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Continue", action: onFinished)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
