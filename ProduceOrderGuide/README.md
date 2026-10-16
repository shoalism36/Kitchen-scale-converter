# Produce Order Guide

1. `brew install xcodegen`
2. `cd ProduceOrderGuide && xcodegen`
3. Open `ProduceOrderGuide.xcodeproj`, set your Team under Signing, run on device (camera scanner needs a real iPhone).

No XcodeGen? New iOS App project (SwiftUI, iOS 17), drag in everything under `Sources/` (check "Copy" + target membership; products.json must be in Copy Bundle Resources) and `Assets.xcassets`, add `NSCameraUsageDescription` to Info.
