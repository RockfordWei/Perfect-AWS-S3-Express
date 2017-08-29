import cURL
import Foundation
import PerfectCrypto
import PerfectCURL
import PerfectLib
import PerfectThread

open class AWS {

  public static var debug = false

  open class Access {
    var key = ""
    var secret = ""
    var timestamp = ""

    public func update() {
      let fmt = DateFormatter()
      fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
      timestamp = fmt.string(from: Date())
    }
    public init(accessKey: String, accessSecret: String) {
      key = accessKey
      secret = accessSecret
      update()
    }

    public func signV4(_ string: String) -> String {
      var bytes = string.sign(.sha1, key: HMACKey(secret))?.encode(.base64)
      bytes?.append(0)
      if let b = bytes {
        return String(cString: b)
      } else {
        return ""
      }
    }
  }

  public enum Exception: Error {
    case UnknownHost
    case InvalidFile
    case InvalidHeader
  }

  open class S3 {
    public static let hosts: [String: String] = [
      "us-east-1": "s3.amazonaws.com",
      "us-east-2": "s3.us-east-2.amazonaws.com",
      "us-west-1": "s3-us-west-1.amazonaws.com",
      "us-west-2": "s3-us-west-2.amazonaws.com",
      "eu-west-1": "s3-eu-west-1.amazonaws.com",
      "eu-central-1": "s3.eu-central-1.amazonaws.com",
      "ap-south-1": "s3.ap-south-1.amazonaws.com",
      "ap-southeast-1": "s3-ap-southeast-1.amazonaws.com",
      "ap-southeast-2": "s3-ap-southeast-2.amazonaws.com",
      "ap-northeast-1": "s3-ap-northeast-1.amazonaws.com",
      "ap-northeast-2": "s3.ap-northeast-2.amazonaws.com",
      "sa-east-1": "s3-sa-east-1.amazonaws.com"
    ]

    private static func prepare(_ access: Access, method: String, bucket: String, region: String, file: String, contentType: String) throws -> (CURL, UnsafeMutablePointer<curl_slist>) {
      guard let host = hosts[region] else {
        throw Exception.UnknownHost
      }


      access.update()
      let resource = "/\(bucket)/\(file)"
      let stringToSign = "\(method)\n\n\(contentType)\n\(access.timestamp)\n\(resource)"
      let signature = access.signV4(stringToSign)
      let url = "https://\(bucket).\(host)/\(file)"
      let curl = CURL(url: url)

      if AWS.debug {
        _ = curl.setOption(CURLOPT_VERBOSE, int: 1)
        _ = curl.setOption(CURLOPT_STDERR, v: stdout)
      }

      var headers: UnsafeMutablePointer<curl_slist>? = nil
      headers = curl_slist_append(headers, "Host: \(bucket).\(host)")
      headers = curl_slist_append(headers, "Date: \(access.timestamp)")
      headers = curl_slist_append(headers, "Content-Type: \(contentType)")
      headers = curl_slist_append(headers, "Authorization: AWS \(access.key):\(signature)")

      _ = curl.setOption(CURLOPT_FOLLOWLOCATION, int: 1)
      guard let list = headers else {
        throw Exception.InvalidHeader
      }
      _ = curl.setOption(CURLOPT_HTTPHEADER, v: list)
      return (curl, list)
    }

    public static func delete(_ access: Access, bucket: String, region: String, file: String, contentType: String) throws {

      let (curl, headers) = try prepare(access, method: "DELETE", bucket: bucket, region: region, file: file, contentType: contentType)

      _ = curl.setOption(CURLOPT_CUSTOMREQUEST, s: "DELETE")
      let (code, _, _) = curl.performFully()
      guard code == 0 else {
        throw Exception.InvalidFile
      }
      curl_slist_free_all(headers)
    }

    public static func download(_ access: Access, bucket: String, region: String, file: String, contentType: String) throws -> [UInt8] {

      let (curl, headers) = try prepare(access, method: "GET", bucket: bucket, region: region, file: file, contentType: contentType)

      _ = curl.setOption(CURLOPT_HTTPGET, int: 1)

      let (code, _, body) = curl.performFully()
      guard code == 0 else {
        throw Exception.InvalidFile
      }
      curl_slist_free_all(headers)
      return body
    }

    public static func upload(_ access: Access, bucket: String, region: String, file: String, contentType: String) throws {

      var fileInfo = stat()
      stat(file, &fileInfo)

      guard fileInfo.st_size > 0,
        let fpointer = fopen(file, "rb") else {
          throw Exception.InvalidFile
      }

      let (curl, headers) = try prepare(access, method: "PUT", bucket: bucket, region: region, file: file, contentType: contentType)

      _ = curl.setOption(CURLOPT_INFILESIZE_LARGE, int: fileInfo.st_size)
      _ = curl.setOption(CURLOPT_READDATA, v: fpointer)
      _ = curl.setOption(CURLOPT_UPLOAD, int: 1)
      _ = curl.setOption(CURLOPT_PUT, int: 1)
      _ = curl.setOption(CURLOPT_READFUNCTION, f: { ptr, size, nitems, stream in
        if let fstream = stream {
          let f = fstream.assumingMemoryBound(to: FILE.self)
          return fread(ptr, size, nitems, f)
        } else {
          return 0
        }
      })

      let (code, _, _) = curl.performFully()
      guard code == 0 else {
        throw Exception.InvalidFile
      }
      curl_slist_free_all(headers)
    }
  }
}

