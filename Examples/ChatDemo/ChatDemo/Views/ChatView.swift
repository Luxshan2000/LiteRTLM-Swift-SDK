import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var vm

    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        if vm.modelReady {
            chatView
        } else {
            modelSetupView
        }
    }

    // MARK: - Setup

    private var modelSetupView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text("LiteRTLM Chat")
                .font(.title3.bold())
            Text("On-device Gemma 4")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if vm.isModelLoading {
                VStack(spacing: 10) {
                    ProgressView(value: vm.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if vm.downloadSpeed > 0 {
                        Text("\(Int(vm.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                @Bindable var vm = vm

                // Backend picker
                Picker("Backend", selection: $vm.selectedBackend) {
                    Label("CPU", systemImage: "cpu")
                        .tag("cpu")
                    Label("GPU (Metal)", systemImage: "gpu")
                        .tag("gpu")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Text(vm.selectedBackend == "gpu"
                     ? "Faster inference via Metal"
                     : "Compatible with all devices")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

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
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // MARK: - Chat

    private var chatView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.last?.text) {
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                headerBar
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Gemma 4")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    if vm.isGenerating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                    Text(vm.isGenerating ? "Generating..." : "On-device")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { vm.cleanup() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Color(.secondarySystemBackground)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        @Bindable var vm = vm

        return VStack(spacing: 0) {
            // Pending image
            if let imageData = vm.pendingImage,
               let uiImage = UIImage(data: imageData) {
                HStack(spacing: 8) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button { vm.pendingImage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            // Recording indicator
            if vm.speech.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("Recording audio...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap mic to stop")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            // Pending audio indicator
            if vm.pendingAudio != nil {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Audio attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { vm.pendingAudio = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Plus menu
                Menu {
                    Section("Photo") {
                        Button {
                            vm.showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        Button {
                            vm.showPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                    }
                    Section("Audio") {
                        Button {
                            Task { await vm.toggleVoice() }
                        } label: {
                            Label(
                                vm.speech.isRecording ? "Stop Recording" : "Record Voice",
                                systemImage: vm.speech.isRecording ? "stop.circle" : "mic"
                            )
                        }
                        Button {
                            vm.showAudioPicker = true
                        } label: {
                            Label("Audio File", systemImage: "waveform")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }
                .photosPicker(isPresented: $vm.showPhotoPicker, selection: $selectedPhoto, matching: .images)
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            vm.pendingImage = data
                        }
                        selectedPhoto = nil
                    }
                }

                // Text field
                TextField("Message", text: $vm.inputText, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .focused($isInputFocused)

                // Send / Stop
                if vm.isGenerating {
                    Button { vm.stopGenerating() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray4))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background {
            Color(.secondarySystemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canSend: Bool {
        !vm.isGenerating &&
        (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         || vm.pendingImage != nil
         || vm.pendingAudio != nil)
    }

    private func sendMessage() {
        guard canSend else { return }
        isInputFocused = false
        Task { await vm.send() }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .system {
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                if message.isUser { Spacer(minLength: 60) }

                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                    if let imageData = message.image,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if !message.text.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                            .font(.body)
                            .foregroundStyle(message.isUser ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(message.isUser ? Color.blue : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                if !message.isUser { Spacer(minLength: 60) }
            }
        }
    }
}

#Preview {
    ChatView()
        .environment(ChatViewModel())
}
