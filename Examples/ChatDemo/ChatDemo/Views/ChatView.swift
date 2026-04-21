import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var vm

    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.modelReady {
                    modelSetupView
                } else {
                    messageList
                    inputBar
                }
            }
            .navigationTitle("ChatDemo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vm.modelReady {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reset") { vm.cleanup() }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Model Setup

    private var modelSetupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("LiteRTLM Chat Demo")
                .font(.title2.bold())

            Text("On-device LLM powered by Gemma 4")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if vm.isModelLoading {
                VStack(spacing: 12) {
                    ProgressView(value: vm.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)

                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await vm.loadModel() }
                } label: {
                    Label("Load Model", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: vm.messages.count) {
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        @Bindable var vm = vm

        return VStack(spacing: 0) {
            Divider()

            // Pending image preview
            if let imageData = vm.pendingImage,
               let uiImage = UIImage(data: imageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    Button {
                        vm.pendingImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Voice transcript preview
            if vm.speech.isListening {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text(vm.speech.transcript.isEmpty
                         ? "Listening..."
                         : vm.speech.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack(spacing: 12) {
                // Photo picker
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    Image(systemName: "photo.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            vm.pendingImage = data
                        }
                        selectedPhoto = nil
                    }
                }

                // Voice button
                Button {
                    Task { await vm.toggleVoice() }
                } label: {
                    Image(systemName: vm.speech.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(vm.speech.isListening ? .red : Color.accentColor)
                }

                // Text field
                TextField("Message...", text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray4))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !vm.isGenerating &&
        (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         || vm.pendingImage != nil)
    }

    private func sendMessage() {
        guard canSend else { return }
        isInputFocused = false
        Task { await vm.send() }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 48) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                if let imageData = message.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .font(.body)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if !message.isUser { Spacer(minLength: 48) }
        }
    }

    private var textColor: Color {
        message.isUser ? .white : .primary
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .model: return Color(.systemGray6)
        case .system: return Color(.systemGray5)
        }
    }
}

#Preview {
    ChatView()
        .environment(ChatViewModel())
}
