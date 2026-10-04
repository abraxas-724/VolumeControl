# Changelog

All notable changes to VolumeControl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Keyboard shortcuts support
- Volume preset save/restore
- Multi-language support (English, 中文)
- Notification center integration

## [1.0.0] - 2024-10-04

### Added
- Initial release of VolumeControl
- System volume control with real-time slider
- Volume percentage display (0-100%)
- Mute/unmute toggle
- Default audio device display
- Automatic device hotplug detection
- Running audio applications monitoring
- Application icon and name display
- Login at startup option
- Settings panel
- Menu bar icon
- Native SwiftUI interface
- Core Audio integration
- 8 unit tests with 100% pass rate

### Technical
- Built with Swift 5.9+
- Supports macOS 14.0+
- Uses Swift Package Manager
- Clean architecture with layered design
- Comprehensive error handling
- Real-time audio device monitoring

### Known Limitations
- System-level volume control only (no per-app volume control)
- Requires macOS 14.0 or later
- No keyboard shortcuts in this version

## [0.1.0] - 2024-09-30

### Added
- Project setup and initial development
- P0-P2 milestone completion
- Basic audio service implementation
- Device monitoring
- Application discovery

---

## Version History

- **v1.0.0** (2024-10-04) - Initial public release
- **v0.1.0** (2024-09-30) - Internal development version

---

## Upgrade Notes

### From Development to v1.0.0

First public release. No upgrade path needed.

### Future Upgrades

Upgrade instructions will be provided with each new release.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this changelog.

---

[Unreleased]: https://github.com/yourusername/VolumeControl/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yourusername/VolumeControl/releases/tag/v1.0.0
[0.1.0]: https://github.com/yourusername/VolumeControl/releases/tag/v0.1.0
