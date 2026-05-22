import Testing
@testable import Camera

@Suite("CameraPermissionResolver")
struct CameraPermissionResolverTests {

    @Test
    func authorizedProviderReturnsAuthorizedWithoutRequesting() async {
        let provider = StubPermissionProvider(status: .authorized, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .authorized)
        #expect(provider.didCallRequest == false)
    }

    @Test
    func notDeterminedAndGrantedReturnsAuthorized() async {
        let provider = StubPermissionProvider(status: .notDetermined, grants: true)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .authorized)
        #expect(provider.didCallRequest == true)
    }

    @Test
    func notDeterminedAndDeniedReturnsDenied() async {
        let provider = StubPermissionProvider(status: .notDetermined, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
        #expect(provider.didCallRequest == true)
    }

    @Test
    func deniedProviderReturnsDeniedWithoutRequesting() async {
        let provider = StubPermissionProvider(status: .denied, grants: true)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
        #expect(provider.didCallRequest == false)
    }

    @Test
    func restrictedProviderReturnsDenied() async {
        let provider = StubPermissionProvider(status: .restricted, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
    }
}

// MARK: - Stub

private final class StubPermissionProvider: CameraPermissionProviding, @unchecked Sendable {
    let initialStatus: CameraAuthorizationStatus
    let grantOnRequest: Bool
    var didCallRequest = false

    init(status: CameraAuthorizationStatus, grants: Bool) {
        self.initialStatus = status
        self.grantOnRequest = grants
    }

    func currentStatus() -> CameraAuthorizationStatus { initialStatus }

    func requestAccess() async -> Bool {
        didCallRequest = true
        return grantOnRequest
    }
}
