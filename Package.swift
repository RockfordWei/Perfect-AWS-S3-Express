import PackageDescription
import Foundation

let url: String
if let cache = getenv("URL_PERFECT"), let local = String(validatingUTF8: cache) {
  url = "\(local)/Perfect-CURL"
} else {
  url = "https://github.com/PerfectlySoft/Perfect-CURL.git"
}

let package = Package(
    name: "PerfectAWS",
    dependencies: [
      .Package(url: url, majorVersion: 3)
    ]
)
