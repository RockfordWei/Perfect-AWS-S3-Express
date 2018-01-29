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
        var date = ""
        
        public func update() {
            let fmt = DateFormatter()
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            timestamp = fmt.string(from: Date())
            
            fmt.dateFormat = "yyyyMMdd"
            date = fmt.string(from: Date())
        }
        
        public init(accessKey: String, accessSecret: String) {
            key = accessKey
            secret = accessSecret
            update()
        }
        
        public func signV4(_ region: String, _ headerDigest: String) throws -> String {
            let stringToSign = """
            AWS4-HMAC-SHA256
            \(timestamp)
            \(date)/\(region)/s3/aws4_request
            \(headerDigest)
            """
            
            let awsSecretKey = "AWS4"+secret
            
            guard let kDate = date.sign(.sha256, key: HMACKey(awsSecretKey)),
                let kRegion = region.sign(.sha256, key: HMACKey(kDate)),
                let kService = "s3".sign(.sha256, key: HMACKey(kRegion)),
                let kSigning = "aws4_request".sign(.sha256, key: HMACKey(kService)),
                let signature = stringToSign.sign(.sha256, key: HMACKey(kSigning)),
                let signatureBytes = signature.encode(.hex) else {
                    throw Exception.CannotSign
            }
            
            let signatureString = String(cString: signatureBytes)
            
            return signatureString
        }
    }
    
    public enum Exception: Error {
        case UnknownHost
        case InvalidFile
        case InvalidHeader
        case CannotSign
    }
    
    open class S3 {
        public static let hosts: [String: String] = [
            "us-east-1": "s3.amazonaws.com",
            "us-east-2": "s3.us-east-2.amazonaws.com",
            "us-west-1": "s3-us-west-1.amazonaws.com",
            "us-west-2": "s3-us-west-2.amazonaws.com",
            "eu-west-1": "s3-eu-west-1.amazonaws.com",
            "eu-west-2": "s3-eu-west-2.amazonaws.com",
            "eu-west-3": "s3-eu-west-3.amazonaws.com",
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
            
            let header = """
            \(method)
            /\(file)
            
            host:\(bucket).\(host)
            x-amz-date:\(access.timestamp)
            
            host;x-amz-date
            UNSIGNED-PAYLOAD
            """
            
            guard let headerDigestHex = header.digest(.sha256)?.encode(.hex), let headerDigest = String(data: Data(headerDigestHex), encoding: .utf8) else {
                throw Exception.CannotSign
            }
            
            do {
                let signatureString = try access.signV4(region, headerDigest)
                let authorization = "AWS4-HMAC-SHA256 Credential=\(access.key)/\(access.date)/\(region)/s3/aws4_request, SignedHeaders=host;x-amz-date, Signature=\(signatureString)"
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
                headers = curl_slist_append(headers, "x-amz-content-sha256: UNSIGNED-PAYLOAD")
                headers = curl_slist_append(headers, "x-amz-date: \(access.timestamp)")
                headers = curl_slist_append(headers, "Authorization: \(authorization)")
                
                _ = curl.setOption(CURLOPT_FOLLOWLOCATION, int: 1)
                guard let list = headers else {
                    throw Exception.InvalidHeader
                }
                _ = curl.setOption(CURLOPT_HTTPHEADER, v: list)
                return (curl, list)
            } catch {
                throw Exception.CannotSign
            }
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

