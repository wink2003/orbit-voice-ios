import Foundation

// Pure executable checks for the privacy boundary. The app target's parser is
// deliberately tiny and can be compiled with this file by CI on a Swift host.
@main
enum OrbitCodecFmtpParserTests {
    static func main() {
        let parsed = OrbitCodecFmtpParser.parse("minptime=10;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxaveragebitrate=48000;cbr=1")
        expect(parsed?["useinbandfec"] == "1", "FEC is retained")
        expect(parsed?["spropStereo"] == "0", "sprop-stereo is normalized")
        expect(parsed?["unknown"] == nil, "unknown keys are omitted")
        expect(OrbitCodecFmtpParser.parseRedPayloads("111/111") == [111, 111], "RED mapping is retained")
        expect(OrbitCodecFmtpParser.parseRedPayloads("111/999") == nil, "invalid RED mapping fails closed")
        expect(OrbitCodecFmtpParser.parse(nil) == nil, "absent fmtp is safe")
        expect(OrbitCodecFmtpParser.parse("usedtx=1;broken") == nil, "malformed fmtp fails closed")
        expect(OrbitCodecFmtpParser.parse("a=1;secret=token") == nil, "non-whitelisted fmtp emits nothing")
        print("OrbitCodecFmtpParserTests: PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}
