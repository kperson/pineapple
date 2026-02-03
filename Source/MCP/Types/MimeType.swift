import Foundation

public enum MimeType: CustomStringConvertible, Equatable, Codable {
    // Text & Documents
    case textPlain
    case textHTML
    case textCSS
    case textJavaScript
    case textCSV
    case textXML
    case applicationJSON
    case applicationXML
    case applicationPDF
    case applicationMSWord
    case applicationWordDocument
    case applicationMSExcel
    case applicationExcelDocument
    case applicationMSPowerPoint
    case applicationPowerPointDocument
    case markdown
    
    // Images
    case imageJPEG
    case imagePNG
    case imageGIF
    case imageWebP
    case imageSVG
    case imageBMP
    case imageTIFF
    case imageIcon
    
    // Audio
    case audioMPEG
    case audioWAV
    case audioOGG
    case audioMP4
    case audioWebM
    
    // Video
    case videoMP4
    case videoWebM
    case videoOGG
    case videoAVI
    case videoQuickTime
    
    // Archives & Executables
    case applicationZIP
    case applicationRAR
    case applicationTAR
    case applicationGZIP
    case applicationOctetStream
    case applicationExecutable
    
    // Web & API
    case applicationJavaScript
    case applicationRSS
    case applicationAtom
    
    // Fonts
    case fontWOFF
    case fontWOFF2
    case fontTTF
    case fontOTF
    
    // Other
    case applicationRTF
    case textCalendar
    case custom(String)
    
    public var description: String {
        switch self {
        case .textPlain: return "text/plain"
        case .textHTML: return "text/html"
        case .textCSS: return "text/css"
        case .textJavaScript: return "text/javascript"
        case .textCSV: return "text/csv"
        case .textXML: return "text/xml"
        case .applicationJSON: return "application/json"
        case .applicationXML: return "application/xml"
        case .applicationPDF: return "application/pdf"
        case .applicationMSWord: return "application/msword"
        case .applicationWordDocument: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .applicationMSExcel: return "application/vnd.ms-excel"
        case .applicationExcelDocument: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .applicationMSPowerPoint: return "application/vnd.ms-powerpoint"
        case .applicationPowerPointDocument: return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case .markdown: return "text/markdown"
        case .imageJPEG: return "image/jpeg"
        case .imagePNG: return "image/png"
        case .imageGIF: return "image/gif"
        case .imageWebP: return "image/webp"
        case .imageSVG: return "image/svg+xml"
        case .imageBMP: return "image/bmp"
        case .imageTIFF: return "image/tiff"
        case .imageIcon: return "image/x-icon"
        case .audioMPEG: return "audio/mpeg"
        case .audioWAV: return "audio/wav"
        case .audioOGG: return "audio/ogg"
        case .audioMP4: return "audio/mp4"
        case .audioWebM: return "audio/webm"
        case .videoMP4: return "video/mp4"
        case .videoWebM: return "video/webm"
        case .videoOGG: return "video/ogg"
        case .videoAVI: return "video/avi"
        case .videoQuickTime: return "video/quicktime"
        case .applicationZIP: return "application/zip"
        case .applicationRAR: return "application/x-rar-compressed"
        case .applicationTAR: return "application/x-tar"
        case .applicationGZIP: return "application/gzip"
        case .applicationOctetStream: return "application/octet-stream"
        case .applicationExecutable: return "application/x-msdownload"
        case .applicationJavaScript: return "application/javascript"
        case .applicationRSS: return "application/rss+xml"
        case .applicationAtom: return "application/atom+xml"
        case .fontWOFF: return "font/woff"
        case .fontWOFF2: return "font/woff2"
        case .fontTTF: return "font/ttf"
        case .fontOTF: return "font/otf"
        case .applicationRTF: return "application/rtf"
        case .textCalendar: return "text/calendar"
        case .custom(let mimeType): return mimeType
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        
        switch stringValue {
        case "text/plain": self = .textPlain
        case "text/html": self = .textHTML
        case "text/css": self = .textCSS
        case "text/javascript": self = .textJavaScript
        case "text/csv": self = .textCSV
        case "text/xml": self = .textXML
        case "application/json": self = .applicationJSON
        case "application/xml": self = .applicationXML
        case "application/pdf": self = .applicationPDF
        case "application/msword": self = .applicationMSWord
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": self = .applicationWordDocument
        case "application/vnd.ms-excel": self = .applicationMSExcel
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": self = .applicationExcelDocument
        case "application/vnd.ms-powerpoint": self = .applicationMSPowerPoint
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": self = .applicationPowerPointDocument
        case "image/jpeg": self = .imageJPEG
        case "image/png": self = .imagePNG
        case "image/gif": self = .imageGIF
        case "image/webp": self = .imageWebP
        case "image/svg+xml": self = .imageSVG
        case "image/bmp": self = .imageBMP
        case "image/tiff": self = .imageTIFF
        case "image/x-icon": self = .imageIcon
        case "audio/mpeg": self = .audioMPEG
        case "audio/wav": self = .audioWAV
        case "audio/ogg": self = .audioOGG
        case "audio/mp4": self = .audioMP4
        case "audio/webm": self = .audioWebM
        case "video/mp4": self = .videoMP4
        case "video/webm": self = .videoWebM
        case "video/ogg": self = .videoOGG
        case "video/avi": self = .videoAVI
        case "video/quicktime": self = .videoQuickTime
        case "application/zip": self = .applicationZIP
        case "application/x-rar-compressed": self = .applicationRAR
        case "application/x-tar": self = .applicationTAR
        case "application/gzip": self = .applicationGZIP
        case "application/octet-stream": self = .applicationOctetStream
        case "application/x-msdownload": self = .applicationExecutable
        case "application/javascript": self = .applicationJavaScript
        case "application/rss+xml": self = .applicationRSS
        case "application/atom+xml": self = .applicationAtom
        case "font/woff": self = .fontWOFF
        case "font/woff2": self = .fontWOFF2
        case "font/ttf": self = .fontTTF
        case "font/otf": self = .fontOTF
        case "application/rtf": self = .applicationRTF
        case "text/calendar": self = .textCalendar
        case "text/markdown": self = .markdown
        case "text/x-markdown": self = .markdown
        default: self = .custom(stringValue)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
