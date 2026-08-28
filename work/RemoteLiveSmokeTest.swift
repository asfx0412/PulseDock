import Foundation

@main
enum RemoteLiveSmokeTest {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: RemoteLiveSmokeTest <ssh-alias>\n".utf8))
            exit(64)
        }
        let alias = CommandLine.arguments[1]
        let device = RemoteDeviceConfiguration(name: alias, sshAlias: alias)
        let snapshot = await SSHMonitorService().probe(device)
        print("health=\(snapshot.health.rawValue) message=\(snapshot.message) gpus=\(snapshot.gpus.count) processes=\(snapshot.gpuProcesses.count)")
        if snapshot.health == .offline { exit(2) }
    }
}
