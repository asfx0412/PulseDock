import Foundation

@main
enum ClashControllerSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    static func main() async {
        let service = ClashControllerService()
        let invalid = await service.inspect(baseURL: "https://example.com:9090", secret: "")
        require(!invalid.reachable && invalid.evidence.contains("只允许"), "控制器不得允许非本机地址")
        let malformed = await service.synchronize(baseURL: "not a url", secret: "")
        require(!malformed.success && malformed.evidence.contains("地址无效"), "无效控制器地址必须有可读原因")
        require(ClashControllerService.isAllowedLocalAddress("unix:///tmp/verge/verge-mihomo.sock"), "Clash Verge Unix controller socket must be an allowed local address")
        require(!ClashControllerService.isAllowedLocalAddress("unix:///tmp/other.sock"), "arbitrary Unix sockets must not be accepted")
        print("Clash controller 6.6 validation self-test passed")
    }
}
