// swift-tools-version: 5.9

// Swift Playgrounds Package Manifest for NOVA
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "NOVA",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "NOVA",
            targets: ["AppModule"],
            bundleIdentifier: "com.nova.assistant",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .sparkle),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .calendars(purposeString: "NOVA accesses your calendar to schedule and verify your events locally."),
                .reminders(purposeString: "NOVA accesses your reminders to create and verify your to-do items locally."),
                .microphone(purposeString: "NOVA accesses the microphone for on-device voice conversations."),
                .speechRecognition(purposeString: "NOVA transcribes your voice completely on-device without network connectivity.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
