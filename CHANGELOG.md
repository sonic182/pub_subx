# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Repositioned `pub_subx` as a lightweight event router focused on hierarchical topics, filtering, and observable delivery.
- Deliver `%PubSubx.Event{}` envelopes to subscribers instead of raw published payloads.
- Documented best-effort distributed publish semantics and clarified public API argument order.

### Added
- Hierarchical topic matching for binary subscriptions with `*` and `**`.
- Subscriber-side filters through `subscribe/4`.
- Envelope metadata support through `publish/4`.
- Telemetry hooks for subscribe, unsubscribe, publish, delivery, drops, and subscriber counts.
- Forwarding support for the new `subscribe/3` and `publish/3` option arities in `PubSubx.Auto`.
- Telemetry-backed best-effort distributed publish summaries in `PubSubx.Utils`.
- Benchmark scaffolding for `PubSubx`, `Phoenix.PubSub`, and `Registry`.

### Changed
- `PubSubx.Utils.distribute_publish/4` now delivers locally by default and only skips
  the current node when `include_local?: false` is passed.

## [0.2.3] - 2024-09-01

### Fix
- A bit fix in docs
- Utils mod for distribute_publish

## [0.2.2] - 2024-09-01

### Added
- Better descriptions for mix.exs

## [0.2.1] - 2024-09-01

### Added
- Registry options in start_link args

## [0.2.0] - 2024-09-01

### Changed
- PubSubx methods to specify pubsub process at first

### Added
- PubSubx.Auto mod for easier usage
- more docs


## [0.1.2] - 2024-09-01

### Added
- Comprehensive module documentation for `PubSubx`, including detailed explanations of functions and usage examples.
- A `README.md` with an overview of the project, installation instructions, usage examples, and contribution guidelines.
- A `CHANGELOG.md` to track changes to the project.

## [0.1.1] - 2022-12-02

### Added
- Initial implementation of the `PubSubx` library, providing basic publish-subscribe functionality.
- Core features:
  - Topic subscription and unsubscription.
  - Message publishing to topics.
  - Listing of subscribers and topics.
  - Automatic cleanup of subscriptions when processes terminate.
