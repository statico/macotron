import Testing
@testable import Modules

@Suite("NetworkPing")
struct NetworkPingTests {
    @Test("reads time= from ping stdout")
    func parseReply() {
        let out = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=56 time=12.3 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 12.3/12.3/12.3/0.000 ms
        """
        #expect(NetworkPing.parse(out) == 12.3)
    }

    @Test("timeouts have no time=")
    func parseTimeout() {
        let out = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        Request timeout for icmp_seq 0
        """
        #expect(NetworkPing.parse(out) == nil)
    }
}
