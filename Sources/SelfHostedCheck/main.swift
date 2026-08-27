import Foundation
import LettersToMyCore

// selfhosted-check — contract checker for the LettersToMy self-hosted server.
//
// Usage: selfhosted-check <baseURL> <apiToken>
//
// Runs the full capability probe (identity, collaboration, backups,
// attachments) against a LIVE server over real HTTP and prints a concise
// report. Exit code 0 when every supported flow passes, 1 otherwise.
// This is the executable proof that the Swift client and the Go server
// agree on the wire contract — see LettersToMy-SelfHostedSync/scripts/
// integration-test.sh which drives it against a freshly started server.

func describe(_ result: Result<String, SelfHostedAPIError>) -> String {
    switch result {
    case .success(let detail): return "PASS — \(detail)"
    case .failure(let error): return "FAIL — \(error.localizedDescription)"
    }
}

func main() async {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        print("usage: selfhosted-check <baseURL> <apiToken>")
        exit(2)
    }
    let baseURL = args[1]
    let token = args[2]

    do {
        let client = try SelfHostedAPIClient(serverURL: baseURL, apiToken: token)
        let check = SelfHostedCapabilityCheck(client: client)
        let report = await check.run()

        if let identity = report.identity {
            print("identity:  \(identity.displayName)")
            print("capabilities: \(identity.capabilities.joined(separator: ", "))")
        } else {
            print("identity:  FAIL — server did not pass identity/version validation")
        }
        print("collaboration: \(describe(report.collaboration))")
        print("backups:       \(describe(report.backups))")
        print("attachments:   \(describe(report.attachments))")

        if report.allPassed {
            print("RESULT: PASS")
            exit(0)
        }
        print("RESULT: FAIL")
        exit(1)
    } catch let error as SelfHostedAPIError {
        print("connection: FAIL — \(error.localizedDescription)")
        exit(1)
    } catch {
        print("connection: FAIL — \(error.localizedDescription)")
        exit(1)
    }
}

await main()