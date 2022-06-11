//
//  ContentView.swift
//  NFCTest
//
//  Created by Jinsan Kim on 2022/06/09.
//

import SwiftUI
import CoreNFC

struct ContentView: View {
    
    @State var data = ""
    @State var showWrite = false
    let holder = "Read message will display here"
    
    var body: some View {
        NavigationView {
            GeometryReader { reader in
                VStack(alignment: .center, spacing: 30) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 20)
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.gray, lineWidth: 4)
                            )
                        Text(self.data.isEmpty ? self.holder : self.data)
                            .foregroundColor(self.data.isEmpty ? .gray : .black)
                            .padding()
                    }
                    .frame(height: reader.size.height * 0.4)
                    .padding()
                    
                    NFCButton(data: self.$data)
                        .frame(width: reader.size.width * 0.9, height: reader.size.height * 0.07)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Write
                    NavigationLink(destination: WriteView(isActive: self.$showWrite), isActive: self.$showWrite) {
                        Button(action: {
                            self.showWrite.toggle()
                        }) {
                            Text("Write NFC")
                                .frame(width: reader.size.width * 0.9, height: reader.size.height * 0.07)
                        }
                        .foregroundColor(.white)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    
                    Spacer()
                }
                .navigationTitle("NFC App")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

struct Payload {
    var type : RecordType
    var pickerMsg : String
}

struct WriteView : View {
    
    @State var record = ""
    @State private var selection = 0
    
    @Binding var isActive : Bool
    
    var sessionWrite = NFCSessionWrite()
    var recordType = [Payload(type: .text, pickerMsg: "Text"), Payload(type: .url, pickerMsg: "URL")]
    
    var body: some View {
        Form {
            Section {
                TextField("Message here...", text: self.$record)
            }
            
            Section {
                Picker(selection: self.$selection, label: Text("Pick a record type")) {
                    ForEach(0..<self.recordType.count) {
                        Text(self.recordType[$0].pickerMsg)
                    }
                }
            }
            
            Section {
                Button(action: {
                    self.sessionWrite.beginScanning(message: self.record, recordType: self.recordType[self.selection].type)
                }) {
                    Text("Write")
                }
            }
            .navigationTitle("NFC Write")
        }
    }
}


// NFC Write
enum RecordType {
    case text, url
}

class NFCSessionWrite : NSObject, NFCNDEFReaderSessionDelegate {
    
    var session : NFCNDEFReaderSession?
    var message = ""
    var recordType : RecordType = .text
    
    func beginScanning(message: String, recordType: RecordType) {
        guard NFCNDEFReaderSession.readingAvailable else {
            print("Scanning not support for this device")
            return
        }
        
        self.message = message
        self.recordType = recordType
        
        session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone"
        session?.begin()
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Do nothing here unless error
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Do nothing here
    }
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Silence console
    }
    
    // Write function
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        // check if only 1 tag found
        if tags.count > 1 {
            // restart session
            let retryInterval = DispatchTimeInterval.milliseconds(2000)
            session.alertMessage = "More than 1 tag is detected"
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            
            return
        }
        
        let tag = tags.first!
        print("Got first tag!")
        session.connect(to: tag) { (error) in
            if error != nil {
                session.alertMessage = "Unable to connect to tag"
                session.invalidate()
                print("Error connect")
                return
            }
            
            tag.queryNDEFStatus { (ndefStatus, capacity, error) in
                if error != nil {
                    session.alertMessage = "Unable to query the NFC NDEF tag"
                    session.invalidate()
                    print("Error query tag")
                    return
                }
                
                switch ndefStatus {
                case .notSupported:
                    print("Not support")
                    session.alertMessage = "Tag is not NDEF complaint"
                    session.invalidate()
                    
                case .readWrite:
                    print("Read write")
                    let payload: NFCNDEFPayload?
                    
                    switch self.recordType {
                    case .text:
                        guard !self.message.isEmpty else {
                            session.alertMessage = "Empty Data"
                            session.invalidate(errorMessage: "Empty text data")
                            return
                        }
                        
                        payload = NFCNDEFPayload.init(format: NFCTypeNameFormat.nfcWellKnown,
                                                      type: "T".data(using: .utf8)!,
                                                      identifier: Data.init(count: 0),
                                                      payload: self.message.data(using: .utf8)!)
                    case .url:
                        guard let url = URL(string: self.message) else {
                            print("Not a valid URL")
                            session.alertMessage = "Unrecognize URL"
                            session.invalidate(errorMessage: "Data is not URL")
                            return
                        }
                        
                        payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url)
                    }
                    
                    // Message array
                    let nfcMessage = NFCNDEFMessage(records: [payload!])
                    
                    // Write to tag
                    tag.writeNDEF(nfcMessage) { (error) in
                        if error != nil {
                            session.alertMessage = "Write NDEF fail: \(error!.localizedDescription)"
                            print("fail write: \(error!.localizedDescription)")
                        } else {
                            session.alertMessage = "Write NDEF successful"
                            print("success write")
                        }
                    }
                    
                case .readOnly:
                    print("Read only")
                    session.alertMessage = "Tag is not read only"
                    session.invalidate()
                    
                @unknown default:
                    print("Unknown error")
                    session.alertMessage = "Unknown NDEF tag status"
                    session.invalidate()
                }
                
            }
        }
    }
}



// NFC Read
struct NFCButton : UIViewRepresentable {
    
    @Binding var data : String
    
    func makeUIView(context: UIViewRepresentableContext<NFCButton>) -> UIButton {
        let button = UIButton()
        button.setTitle("Read NFC", for: .normal)
        button.backgroundColor = UIColor.black
        button.addTarget(context.coordinator, action: #selector(context.coordinator.beginScan(_:)), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: UIButton, context: UIViewRepresentableContext<NFCButton>) {
        // do nothing
    }
    
    func makeCoordinator() -> NFCButton.Coordinator {
        return Coordinator(data: $data)
    }
    
    
    class Coordinator: NSObject, NFCNDEFReaderSessionDelegate {
        
        var session : NFCNDEFReaderSession?
        @Binding var data : String
        
        init(data: Binding<String>) {
            _data = data
        }
        
        
        @objc func beginScan(_ sender: Any) {
            guard NFCNDEFReaderSession.readingAvailable else {
                print("error: Scanning not support")
                return
            }
            
            session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            session?.alertMessage = "Hold your iPhone near to scan"
            session?.begin()
            
        }
        
        func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
            // Check the invalidation reason from the returned error.
            if let readerError = error as? NFCReaderError {
                // Show an alert when the invalidation reason is not because of a
                // successful read during a single-tag read session, or because the
                // user canceled a multiple-tag read session from the UI or
                // programmatically using the invalidate method call.
                if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                    && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                    print("Error NFC read: \(readerError.localizedDescription)")
                }
            }

            // To read new tags, a new session instance is required.
            self.session = nil
        }
        
        func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
            guard
                let nfcMess = messages.first,
                let record = nfcMess.records.first,
                record.typeNameFormat == .absoluteURI || record.typeNameFormat == .nfcWellKnown,
                let payload = String(data: record.payload, encoding: .utf8)
            else {
                return
            }
            
            print(payload)
            self.data = payload
        }
        
        
    }
    
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
