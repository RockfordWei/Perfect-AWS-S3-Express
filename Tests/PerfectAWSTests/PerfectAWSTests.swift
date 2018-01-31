import XCTest
@testable import PerfectAWS
import PerfectLib

extension String {

  public var sysEnv: String {
    guard let e = getenv(self) else { return "" }
    return String(cString: e)
  }

}

class PerfectAWSTests: XCTestCase {

  var region = "REGION".sysEnv
  var bucket = "BUCKET".sysEnv
  var fileName = "hello.txt"
  var fileContent = "hello, world!\n\n"
  var contentType = "text/plain"
  var access = AWS.Access(accessKey: "ACSKEY".sysEnv, accessSecret: "ACSPWD".sysEnv)

  override func setUp() {
    AWS.debug = true
    chdir("/tmp")
    let file = File(fileName)
    _ = try? file.open(.write)
    _ = try? file.write(string: fileContent)
    file.close()
  }

  override func tearDown() {
    unlink(fileName)
  }
  
  func testSign() {
//    let acs = access
//    acs.timestamp = "Sun, 27 Aug 2017 00:11:23 -0400"
//    let contentType = "text/plain"
//    let resource = "/fishpool/hello.txt"
//    let tosign = "GET\n\n\(contentType)\n\(acs.timestamp)\n\(resource)"
//    let signed = acs.signV4(tosign, <#HMACKey#>)
//    print(tosign)
//    print(signed)
//    XCTAssertEqual(signed, "tlQWvHiCkl7AISfp+tKWCWe2QXw=")
    
    let b = "elyot-sandbox"
    let r = "eu-west-3"
    
    guard let host = AWS.S3.hosts[r] else {
        return
    }
    
    let acs = access
    access.timestamp = "20180129T101809Z"
    access.date = "20180129"
    
    let header = """
    GET
    /fishpool/hello.txt
    
    host:\(b).\(host)
    x-amz-date:\(acs.timestamp)
    
    host;x-amz-date
    UNSIGNED-PAYLOAD
    """
    
    guard let headerDigest = header.digest(.sha256)?.encode(.hex) else {
        XCTFail(AWS.Exception.CannotSign.localizedDescription)
        return
    }
    
    let headerDigestString = String(cString: headerDigest)
    
    do {
        let signatureString = try access.signV4(region, headerDigestString)
        XCTAssertEqual(signatureString, "6b555ea915ec8a5ee592ccfeec21a4d8d0ee27cfb29c8349fd80118f462ec23b")
    } catch {
        XCTFail(error.localizedDescription)
        return
    }
  }

  func testSample() {
    do {

      try AWS.S3.upload(access, bucket: bucket, region: region, file: fileName, contentType: contentType)

      var bytes = try AWS.S3.download(access, bucket: bucket, region: region, file: fileName, contentType: contentType)
      bytes.append(0)
      let string = String(cString: bytes)
      XCTAssertEqual(string, fileContent)

      try AWS.S3.delete(access, bucket: bucket, region: region, file: fileName, contentType: contentType)
    }catch{
      XCTFail(error.localizedDescription)
    }
  }

  static var allTests = [
    ("testSample", testSample),
    ("testSign", testSign)
    ]
}
