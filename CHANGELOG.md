# Changelog

All notable changes to QuotaPulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Prepared the repository and documentation for the v0.1.0 release candidate audit.
- Licensed QuotaPulse under the MIT License and created the initial public Git baseline.

## [0.1.0] - Unreleased

### Added

- Native macOS menu bar interface for normalized Codex and experimental Claude Code quota states.
- ChatGPT-integrated Codex app-server discovery, bounded process lifecycle, refresh coordination, local notifications, and local settings.
- English and Traditional Chinese localization.

### Security

- Provider credentials, prompts, transcripts, raw provider responses, and coding history are outside QuotaPulse's data model and logging boundary.
