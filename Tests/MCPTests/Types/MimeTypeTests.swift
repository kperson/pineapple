import Testing
import Foundation
@testable import MCP

@Suite("MimeType Tests")
struct MimeTypeTests {
    
    // MARK: - Description Tests
    
    @Suite("Description")
    struct DescriptionTests {
        
        @Test("Text MIME types have correct descriptions")
        func textMimeTypes() {
            #expect(MimeType.textPlain.description == "text/plain")
            #expect(MimeType.textHTML.description == "text/html")
            #expect(MimeType.textCSS.description == "text/css")
            #expect(MimeType.textJavaScript.description == "text/javascript")
            #expect(MimeType.textCSV.description == "text/csv")
            #expect(MimeType.textXML.description == "text/xml")
            #expect(MimeType.markdown.description == "text/markdown")
            #expect(MimeType.textCalendar.description == "text/calendar")
        }
        
        @Test("Application MIME types have correct descriptions")
        func applicationMimeTypes() {
            #expect(MimeType.applicationJSON.description == "application/json")
            #expect(MimeType.applicationXML.description == "application/xml")
            #expect(MimeType.applicationPDF.description == "application/pdf")
            #expect(MimeType.applicationJavaScript.description == "application/javascript")
            #expect(MimeType.applicationOctetStream.description == "application/octet-stream")
            #expect(MimeType.applicationRTF.description == "application/rtf")
        }
        
        @Test("Image MIME types have correct descriptions")
        func imageMimeTypes() {
            #expect(MimeType.imageJPEG.description == "image/jpeg")
            #expect(MimeType.imagePNG.description == "image/png")
            #expect(MimeType.imageGIF.description == "image/gif")
            #expect(MimeType.imageWebP.description == "image/webp")
            #expect(MimeType.imageSVG.description == "image/svg+xml")
            #expect(MimeType.imageBMP.description == "image/bmp")
            #expect(MimeType.imageTIFF.description == "image/tiff")
            #expect(MimeType.imageIcon.description == "image/x-icon")
        }
        
        @Test("Audio MIME types have correct descriptions")
        func audioMimeTypes() {
            #expect(MimeType.audioMPEG.description == "audio/mpeg")
            #expect(MimeType.audioWAV.description == "audio/wav")
            #expect(MimeType.audioOGG.description == "audio/ogg")
            #expect(MimeType.audioMP4.description == "audio/mp4")
            #expect(MimeType.audioWebM.description == "audio/webm")
        }
        
        @Test("Video MIME types have correct descriptions")
        func videoMimeTypes() {
            #expect(MimeType.videoMP4.description == "video/mp4")
            #expect(MimeType.videoWebM.description == "video/webm")
            #expect(MimeType.videoOGG.description == "video/ogg")
            #expect(MimeType.videoAVI.description == "video/avi")
            #expect(MimeType.videoQuickTime.description == "video/quicktime")
        }
        
        @Test("Archive MIME types have correct descriptions")
        func archiveMimeTypes() {
            #expect(MimeType.applicationZIP.description == "application/zip")
            #expect(MimeType.applicationRAR.description == "application/x-rar-compressed")
            #expect(MimeType.applicationTAR.description == "application/x-tar")
            #expect(MimeType.applicationGZIP.description == "application/gzip")
        }
        
        @Test("Font MIME types have correct descriptions")
        func fontMimeTypes() {
            #expect(MimeType.fontWOFF.description == "font/woff")
            #expect(MimeType.fontWOFF2.description == "font/woff2")
            #expect(MimeType.fontTTF.description == "font/ttf")
            #expect(MimeType.fontOTF.description == "font/otf")
        }
        
        @Test("Office document MIME types have correct descriptions")
        func officeMimeTypes() {
            #expect(MimeType.applicationMSWord.description == "application/msword")
            #expect(MimeType.applicationWordDocument.description == "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
            #expect(MimeType.applicationMSExcel.description == "application/vnd.ms-excel")
            #expect(MimeType.applicationExcelDocument.description == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            #expect(MimeType.applicationMSPowerPoint.description == "application/vnd.ms-powerpoint")
            #expect(MimeType.applicationPowerPointDocument.description == "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        }
        
        @Test("Custom MIME type description")
        func customMimeType() {
            let custom = MimeType.custom("application/x-custom")
            #expect(custom.description == "application/x-custom")
        }
    }
    
    // MARK: - Decoding Tests
    
    @Suite("Decoding")
    struct DecodingTests {
        
        @Test("Decode standard text types")
        func decodeTextTypes() throws {
            let json = "\"text/plain\"".data(using: .utf8)!
            let mimeType = try JSONDecoder().decode(MimeType.self, from: json)
            #expect(mimeType == .textPlain)
        }
        
        @Test("Decode markdown variations")
        func decodeMarkdown() throws {
            let markdown1 = "\"text/markdown\"".data(using: .utf8)!
            let type1 = try JSONDecoder().decode(MimeType.self, from: markdown1)
            #expect(type1 == .markdown)
            
            let markdown2 = "\"text/x-markdown\"".data(using: .utf8)!
            let type2 = try JSONDecoder().decode(MimeType.self, from: markdown2)
            #expect(type2 == .markdown)
        }
        
        @Test("Decode image types")
        func decodeImageTypes() throws {
            let png = "\"image/png\"".data(using: .utf8)!
            let type = try JSONDecoder().decode(MimeType.self, from: png)
            #expect(type == .imagePNG)
        }
        
        @Test("Decode unknown type as custom")
        func decodeUnknown() throws {
            let unknown = "\"application/x-unknown\"".data(using: .utf8)!
            let type = try JSONDecoder().decode(MimeType.self, from: unknown)
            
            if case .custom(let value) = type {
                #expect(value == "application/x-unknown")
            } else {
                Issue.record("Expected custom MIME type")
            }
        }
        
        @Test("Decode complex office document types")
        func decodeOfficeDocuments() throws {
            let docx = "\"application/vnd.openxmlformats-officedocument.wordprocessingml.document\"".data(using: .utf8)!
            let type = try JSONDecoder().decode(MimeType.self, from: docx)
            #expect(type == .applicationWordDocument)
        }
    }
    
    // MARK: - Encoding Tests
    
    @Suite("Encoding")
    struct EncodingTests {
        
        @Test("Encode standard types")
        func encodeStandard() throws {
            let mimeType = MimeType.applicationJSON
            let encoded = try JSONEncoder().encode(mimeType)
            let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
            #expect(decoded == .applicationJSON)
        }
        
        @Test("Encode custom type")
        func encodeCustom() throws {
            let mimeType = MimeType.custom("text/x-custom")
            let encoded = try JSONEncoder().encode(mimeType)
            let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
            
            if case .custom(let value) = decoded {
                #expect(value == "text/x-custom")
            } else {
                Issue.record("Expected custom MIME type after encode/decode")
            }
        }
        
        @Test("Encode image type")
        func encodeImage() throws {
            let mimeType = MimeType.imagePNG
            let encoded = try JSONEncoder().encode(mimeType)
            let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
            #expect(decoded == .imagePNG)
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Suite("Round-trip")
    struct RoundTripTests {
        
        @Test("Round-trip all standard text types")
        func roundTripText() throws {
            let types: [MimeType] = [
                .textPlain, .textHTML, .textCSS, .textJavaScript,
                .textCSV, .textXML, .markdown, .textCalendar
            ]
            
            for type in types {
                let encoded = try JSONEncoder().encode(type)
                let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
                #expect(decoded == type)
            }
        }
        
        @Test("Round-trip all image types")
        func roundTripImage() throws {
            let types: [MimeType] = [
                .imageJPEG, .imagePNG, .imageGIF, .imageWebP,
                .imageSVG, .imageBMP, .imageTIFF, .imageIcon
            ]
            
            for type in types {
                let encoded = try JSONEncoder().encode(type)
                let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
                #expect(decoded == type)
            }
        }
        
        @Test("Round-trip all audio types")
        func roundTripAudio() throws {
            let types: [MimeType] = [
                .audioMPEG, .audioWAV, .audioOGG, .audioMP4, .audioWebM
            ]
            
            for type in types {
                let encoded = try JSONEncoder().encode(type)
                let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
                #expect(decoded == type)
            }
        }
        
        @Test("Round-trip all video types")
        func roundTripVideo() throws {
            let types: [MimeType] = [
                .videoMP4, .videoWebM, .videoOGG, .videoAVI, .videoQuickTime
            ]
            
            for type in types {
                let encoded = try JSONEncoder().encode(type)
                let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
                #expect(decoded == type)
            }
        }
        
        @Test("Round-trip custom type")
        func roundTripCustom() throws {
            let original = MimeType.custom("application/x-special")
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MimeType.self, from: encoded)
            
            if case .custom(let value) = decoded {
                #expect(value == "application/x-special")
            } else {
                Issue.record("Expected custom MIME type")
            }
        }
    }
    
    // MARK: - Equality Tests
    
    @Suite("Equality")
    struct EqualityTests {
        
        @Test("Same types are equal")
        func sameTypesEqual() {
            #expect(MimeType.textPlain == MimeType.textPlain)
            #expect(MimeType.applicationJSON == MimeType.applicationJSON)
            #expect(MimeType.imagePNG == MimeType.imagePNG)
        }
        
        @Test("Different types are not equal")
        func differentTypesNotEqual() {
            #expect(MimeType.textPlain != MimeType.textHTML)
            #expect(MimeType.imagePNG != MimeType.imageJPEG)
            #expect(MimeType.audioMP4 != MimeType.videoMP4)
        }
        
        @Test("Custom types with same value are equal")
        func customTypesEqual() {
            let custom1 = MimeType.custom("application/x-test")
            let custom2 = MimeType.custom("application/x-test")
            #expect(custom1 == custom2)
        }
        
        @Test("Custom types with different values are not equal")
        func customTypesNotEqual() {
            let custom1 = MimeType.custom("application/x-test1")
            let custom2 = MimeType.custom("application/x-test2")
            #expect(custom1 != custom2)
        }
        
        @Test("Standard type not equal to custom with same description")
        func standardNotEqualToCustom() {
            let standard = MimeType.textPlain
            let custom = MimeType.custom("text/plain")
            #expect(standard != custom)
        }
    }
}
