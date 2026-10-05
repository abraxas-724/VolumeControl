#!/bin/sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sh "$ROOT_DIR/scripts/build-app.sh"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.build/routing-validation.XXXXXX")"
PID_A=""
PID_B=""
PID_CONTROL=""
cleanup() {
    for task_pid in "$PID_CONTROL" "$PID_A" "$PID_B"; do
        if [ -n "$task_pid" ]; then kill "$task_pid" 2>/dev/null || true; fi
    done
    if [ -n "$PID_CONTROL" ]; then wait "$PID_CONTROL" 2>/dev/null || true; fi
}
trap cleanup EXIT HUP INT TERM
cat > "$WORK_DIR/Tone.swift" <<'SWIFT'
import AppKit
import AVFoundation
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let engine = AVAudioEngine()
let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
let frequency = Double(CommandLine.arguments[1])!
var phase = 0.0
let source = AVAudioSourceNode(format: format) { _, _, frames, output in
    let buffers = UnsafeMutableAudioBufferListPointer(output)
    for frame in 0..<Int(frames) {
        let value = Float(sin(phase) * 0.01)
        phase += 2 * .pi * frequency / rate
        if phase > 2 * .pi { phase -= 2 * .pi }
        for buffer in buffers {
            let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
            for channel in 0..<Int(buffer.mNumberChannels) {
                samples[frame * Int(buffer.mNumberChannels) + channel] = value
            }
        }
    }
    return noErr
}
engine.attach(source)
engine.connect(source, to: engine.mainMixerNode, format: format)
try engine.start()
app.run()
SWIFT
swiftc "$WORK_DIR/Tone.swift" -o "$WORK_DIR/Tone"
for name in A; do
    bundle="$WORK_DIR/Tone$name.app"
    mkdir -p "$bundle/Contents/MacOS"
    cp "$WORK_DIR/Tone" "$bundle/Contents/MacOS/Tone"
    cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.volumecontrol.validation.tone$name</string>
<key>CFBundleExecutable</key><string>Tone</string>
<key>CFBundleName</key><string>VolumeControl Validation $name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
    codesign --force --sign - "$bundle"
done
"$ROOT_DIR/VolumeControl.app/Contents/MacOS/VolumeControl" --verify-audio-routing "$WORK_DIR/report.json" "$WORK_DIR/ready" > "$WORK_DIR/app.log" 2>&1 &
PID_CONTROL=$!
for attempt in $(seq 1 150); do
    if [ -f "$WORK_DIR/ready" ]; then break; fi
    if [ -f "$WORK_DIR/report.json" ]; then break; fi
    sleep 0.1
done
if [ -f "$WORK_DIR/ready" ]; then
    "$WORK_DIR/ToneA.app/Contents/MacOS/Tone" 440 > "$WORK_DIR/toneA.log" 2>&1 &
    PID_A=$!
fi
wait "$PID_CONTROL" || true
PID_CONTROL=""
python3 - "$WORK_DIR/report.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file: report = json.load(file)
print(json.dumps(report, indent=2, ensure_ascii=False))
sys.exit(0 if report.get('passed') else 1)
PY
