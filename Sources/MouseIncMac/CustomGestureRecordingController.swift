import Combine
import Foundation

@MainActor
final class CustomGestureRecordingController: ObservableObject {
    struct Completion {
        var succeeded: Bool
        var message: String
    }

    @Published private(set) var isRecording = false
    @Published private(set) var recordedSampleCount = 0
    @Published private(set) var targetBindingID: UUID?
    @Published private(set) var statusMessage: String?

    private var samples: [[CGPoint]] = []
    private var completionHandler: (@MainActor ([[CGPoint]]) -> Completion)?

    func start(
        targetBindingID: UUID,
        completion: @escaping @MainActor ([[CGPoint]]) -> Completion
    ) {
        samples = []
        recordedSampleCount = 0
        self.targetBindingID = targetBindingID
        completionHandler = completion
        isRecording = true
        statusMessage = "请按住右键绘制第 1/3 次样本"
    }

    func cancel() {
        isRecording = false
        samples = []
        recordedSampleCount = 0
        completionHandler = nil
        statusMessage = "已取消录制"
    }

    @discardableResult
    func consume(points: [CGPoint]) -> Bool {
        guard isRecording else { return false }
        samples.append(points)
        recordedSampleCount = samples.count

        if samples.count < 3 {
            statusMessage = "已录制 \(samples.count)/3，请继续绘制第 \(samples.count + 1)/3 次"
            return true
        }

        isRecording = false
        let completion = completionHandler?(samples) ?? Completion(
            succeeded: false,
            message: "录制未能完成"
        )
        completionHandler = nil
        samples = []
        statusMessage = completion.message
        if !completion.succeeded {
            recordedSampleCount = 0
        }
        return true
    }
}
