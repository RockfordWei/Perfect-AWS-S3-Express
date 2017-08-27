# AWS S3 Express in Perfect

``` swift
let access = AWS.Access(accessKey: "you-access-key", accessSecret: "you-access-secret")
// upload
try AWS.S3.upload(access, bucket: "myFirstBucket", region: "us-east-1", file: "file-in-current-pty", contentType: "text/plain")

// download
let bytes = try AWS.S3.download(access, bucket: bucket, region: region, file: fileName, contentType: contentType)

// delete
try AWS.S3.delete(access, bucket: bucket, region: region, file: fileName, contentType: contentType)
```
