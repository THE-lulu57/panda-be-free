import Foundation
@testable import Networking
import Testing

struct FTPSServiceTests {
    @Test("Parses a standard PASV reply")
    func parsesPASVReply() {
        let reply = "227 Entering Passive Mode (192,168,1,50,204,130)."
        let result = FTPSService.parsePASVReply(reply)
        #expect(result?.0 == "192.168.1.50")
        #expect(result?.1 == 52354)
    }

    @Test("Returns nil for a malformed PASV reply")
    func rejectsMalformedPASVReply() {
        #expect(FTPSService.parsePASVReply("227 Entering Passive Mode") == nil)
    }

    @Test("Parses a Unix-style LIST listing, including files with spaces")
    func parsesListing() {
        let listing = """
        -rw-r--r-- 1 root root 5242880 Jan 01 12:00 SnoopyV2.gcode.3mf\r
        drwxr-xr-x 2 root root 4096 Jan 01 12:00 cache\r
        -rw-r--r-- 1 root root 1048576 Jan 01 12:01 my model with spaces.gcode.3mf\r
        """
        let data = Data(listing.utf8)
        let entries = FTPSService.parseListing(data)

        #expect(entries.count == 3)
        #expect(entries[0].name == "SnoopyV2.gcode.3mf")
        #expect(entries[0].sizeBytes == 5_242_880)
        #expect(entries[0].isDirectory == false)
        #expect(entries[1].isDirectory == true)
        #expect(entries[2].name == "my model with spaces.gcode.3mf")
    }
}
