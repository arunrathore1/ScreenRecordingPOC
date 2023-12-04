//
//  ContentView.swift
//  Dummy
//
//  Created by Arun Rathore on 17/11/23.
//

import SwiftUI
import ReplayKit
import Photos

enum BlobUploadResult {
    case success
    case failure(Error)
}

struct ContentView: View {
    //     Recording Status
    @State var isRecording: Bool = false
    @State var url: URL?
    var body: some View {
        VStack {
            DummyView()
            Spacer()
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        if isRecording {
                            //Stopping
                            Task {
                                do {
                                    self.url = try await stopRecording()
                                    print(url)
                                    AzureBloobs.uploadBlobSAS(fromfile: url?.path ?? "") { result in
                                        switch result {
                                            case .success:
                                                print("Uploaded Successfully")
                                            case .failure(_):
                                                print("Uploading failed")
                                        }
                                    }
                                    isRecording = false

                                } catch {
                                    print(error.localizedDescription)
                                }
                            }

                        }
                        else {
                            //Stat Recording
                            startRecording { error in
                                if let error = error {
                                    print(error.localizedDescription)
                                    return
                                }
                                //Success
                                isRecording = true

                            }
                        }

                    }, label: {
                        Image(systemName: isRecording ? "record.circle.fill":"record.circle")
                            .font(.largeTitle)
                            .foregroundColor(isRecording ? .red: .black)
                    })
                }.padding()

        }
        .padding()
    }
    private func saveToPhotos(tempURL: URL, completion: @escaping (Bool) -> Void)  {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
        } completionHandler: { success, error in
            if success == true {
                print("Saved rolling clip to photos")
            } else {
                print("Error exporting clip to Photos \(String(describing: error))")
            }
            completion(success)
        }

    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


struct DummyData {
    let title: String
    let description: String
}

struct DummyView: View {
    let dummyData: [DummyData] = [
        DummyData(title: "Item 1", description: "Description for Item 1"),
        DummyData(title: "Item 2", description: "Description for Item 2"),
        DummyData(title: "Item 3", description: "Description for Item 3")
    ]

    var body: some View {
        List(dummyData, id: \.title) { data in
            VStack(alignment: .leading) {
                Text(data.title)
                    .font(.headline)
                Text(data.description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle("Dummy View")
    }
}

struct DummyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DummyView()
        }
    }
}

func presentOnTopViewController(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let topWindow = windowScene.windows.first,
       let topController = topWindow.rootViewController {
        topController.present(viewController, animated: animated, completion: completion)
    }
}

func getConfirmation(url: String) {
    let message = "If you encounter a timeout error, please attempt to upload the video to Azure Blobs again"
    let alert = UIAlertController(title: "System Message", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Retry", style: .default, handler: { alert in
//        AzureBloobs.uploadBlobSAS(fromfile: url)
    }))
    presentOnTopViewController(alert, animated: true, completion: nil)
}



class AzureBloobs: ObservableObject {
    //Upload to Azure Blob Storage with help of SAS
    static func uploadBlobSAS(fromfile: String, completionHandler: @escaping (BlobUploadResult) -> Void){

        // If using a SAS token, fill it in here.  If using Shared Key access, comment out the following line.
        var containerURL = "https://nomrsdevfs1.blob.core.windows.net/video/?sp=rw&st=2022-11-11T17:23:52Z&se=2032-11-12T01:23:52Z&spr=https&sv=2021-06-08&sr=c&sig=oc0UVtEijXo1ORcY8PQhdawCISIHtDNG4d45TDsUS9Y%3D"  //here we have to append sas string: + sas
        print("containerURL with SAS: \(containerURL) ")

       var container: AZSCloudBlobContainer?
       var error: NSError?

       if let containerURL = URL(string: containerURL) {
           container = AZSCloudBlobContainer(url: containerURL, error: &error)

           if let container = container {
               let blob = container.blockBlobReference(fromName: "2023/11/8/8392/1234/123.mp4")
               DispatchQueue.global(qos: .background).async {
                   blob.uploadFromFile(withPath: fromfile, completionHandler: { uploadError in
                       if let uploadError = uploadError {
                           completionHandler(.failure(uploadError))
                           print("Error uploading file: \(uploadError.localizedDescription)")
                       } else {
                           completionHandler(.success)
                           print("File uploaded successfully")
                       }
                   })
               }
           } else {
               if let error = error {
                   print("Error in creating blob container object: \(error.localizedDescription)")
               } else {
                   print("Unknown error creating blob container object")
               }
           }
       } else {
           print("Invalid container URL: \(containerURL)")
       }
    }
}

// App Recording Extension
extension View {
    //    Start Recording
    func startRecording(enabledMicroPhone: Bool = false, completion: @escaping (Error?) -> ()) {
        let recorder = RPScreenRecorder.shared()
        //        MicroPhone Option
        recorder.isMicrophoneEnabled = true
        //        Starting Recording
        recorder.startRecording(handler: completion)
    }

    //     Stop Recording
    //     It will return the record video url
    func stopRecording() async throws -> URL {
        //         File will be stored in temprory directory
        //        Video Name
//        let name = UUID().uuidString + ".mov"
//        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let recorder = RPScreenRecorder.shared()
        let url = getDirectory()
        try await recorder.stopRecording(withOutput: url)
        return url

    }

//     Cancel Recording
    func cancelRecording() {
        let recorder = RPScreenRecorder.shared()
        recorder.discardRecording { }
    }

    private func getDirectory() -> URL {
        var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-hh-mm-ss"
        let stringDate = formatter.string(from: Date())
        tempPath.appendPathComponent(String.localizedStringWithFormat("output-%@.mp4", stringDate))
        return tempPath
    }
}
