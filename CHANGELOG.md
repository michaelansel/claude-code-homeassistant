# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-04

### Added
- Initial release of Claude Code Agent add-on
- c3po multi-agent coordination support
- OAuth token authentication
- Persistent credential storage
- S6 service supervision
- Read-write access to Home Assistant configuration
- Health checks and automatic restart
- Comprehensive documentation (DOCS.md and README.md)

### Features
- Runs as non-root user (UID 1000)
- Multi-architecture support (aarch64, amd64, armv7)
- Automatic c3po plugin installation and enrollment
- Work directory configuration
- Project name customization
- Machine name configuration for c3po identification

### Security
- No Docker socket access required
- No privileged mode required
- OAuth token stored securely by HA Supervisor
- Isolated container environment

[0.1.0]: https://github.com/michaelansel/claude-code-homeassistant/releases/tag/v0.1.0
