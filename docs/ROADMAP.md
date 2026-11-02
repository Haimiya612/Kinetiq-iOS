# Kinetiq --- Development Roadmap

Kinetiq is an independent, native iOS media platform designed to bring
video, manga, images, and music into one unified experience.

The project prioritizes performance, reliability, privacy,
extensibility, and a polished native iOS interface.

------------------------------------------------------------------------

## Phase 1 --- Foundation & Application Architecture

**Goal:** Establish a reliable foundation for the entire application.

-   [x] Create the native iOS application using SwiftUI
-   [x] Establish the main application structure
-   [x] Implement primary tab navigation
-   [x] Establish the initial Kinetiq design language
-   [x] Configure GitHub repository and development workflow
-   [x] Configure GitHub Actions build workflow
-   [x] Successfully build and package an unsigned IPA
-   [x] Establish the initial update log system
-   [ ] Improve project-wide code organization
-   [ ] Establish consistent error handling and logging
-   [ ] Expand automated tests
-   [ ] Improve accessibility and interface consistency

**Status:** Foundation established. Further architectural improvements
remain.

------------------------------------------------------------------------

## Phase 2 --- Playback & Player Experience

**Goal:** Build a reliable, feature-rich native media playback
experience.

### Core Playback

-   [x] Integrate AVPlayer
-   [x] Implement local media playback
-   [x] Build the full-screen player interface
-   [x] Implement playback controls
-   [x] Implement playback speed selection
-   [x] Implement aspect ratio controls
-   [x] Implement audio track selection
-   [x] Implement subtitle selection
-   [x] Implement sleep timer
-   [x] Support importing media through Files and Photos

### Playback Memory

-   [ ] Implement persistent playback history
-   [ ] Remember the last playback position
-   [ ] Automatically resume from the saved position
-   [ ] Add Continue Watching to the Home screen
-   [ ] Display playback progress indicators
-   [ ] Detect completed media
-   [ ] Automatically remove completed entries from Continue Watching
-   [ ] Preserve playback history after app restarts

### Advanced Player Features

-   [ ] Generate video thumbnails
-   [ ] Retrieve and display media metadata
-   [ ] Implement playback queues
-   [ ] Add Picture-in-Picture support
-   [ ] Add AirPlay support
-   [ ] Improve playback error recovery
-   [ ] Improve playback performance and stability
-   [ ] Test different codecs, formats, and resolutions

**Status:** Core playback implemented. Playback Memory is the next
milestone.

------------------------------------------------------------------------

## Phase 3 --- Advanced Media Library

**Goal:** Transform the basic local library into a complete media
management system.

-   [ ] Generate media thumbnails
-   [ ] Retrieve media metadata
-   [ ] Add media categories
-   [ ] Implement favorites
-   [ ] Implement custom collections
-   [ ] Add sorting options
-   [ ] Add filtering options
-   [ ] Implement library search
-   [ ] Support multiple import locations
-   [ ] Improve storage management
-   [ ] Add duplicate media detection
-   [ ] Improve Files and Photos integration

------------------------------------------------------------------------

## Phase 4 --- Discovery & Content Catalogue

**Goal:** Build a unified discovery experience for different types of
media.

-   [ ] Implement the Discover interface
-   [ ] Add featured and trending content sections
-   [ ] Implement cross-category search
-   [ ] Create media detail pages
-   [ ] Support movies and television series
-   [ ] Support seasons and episodes
-   [ ] Implement watchlists
-   [ ] Add recently updated content
-   [ ] Integrate metadata providers
-   [ ] Implement recommendations
-   [ ] Connect discovery results to playback and reading experiences

------------------------------------------------------------------------

## Phase 5 --- Kinetiq Module Engine

**Goal:** Create an extensible module ecosystem that allows external
repositories to provide content and functionality.

### Repository Management

-   [ ] Implement repository management
-   [ ] Support adding external repositories
-   [ ] Parse repository manifests
-   [ ] Build a module catalogue
-   [ ] Display module information and changelogs
-   [ ] Support default repositories

### Module Management

-   [ ] Implement module installation
-   [ ] Implement module uninstallation
-   [ ] Implement module updates
-   [ ] Add version management
-   [ ] Implement compatibility checks
-   [ ] Handle dependencies
-   [ ] Display installation and update progress

### Security & Reliability

-   [ ] Implement SHA-256 package verification
-   [ ] Implement signature verification where supported
-   [ ] Establish repository trust management
-   [ ] Define module permissions and capabilities
-   [ ] Isolate module execution
-   [ ] Implement module error handling
-   [ ] Maintain installation and update history

### Synthetiq Compatibility

-   [ ] Research the Synthetiq module format
-   [ ] Identify the required runtime and host APIs
-   [ ] Understand compatibility requirements
-   [ ] Investigate package and manifest handling
-   [ ] Design a compatibility adapter
-   [ ] Test compatible modules individually
-   [ ] Document supported and unsupported functionality

**Important:** Compatibility with third-party modules depends on their
documented runtime requirements, technical compatibility, signatures,
and applicable permissions. Kinetiq will not bypass security checks or
redistribute packages without authorization.

------------------------------------------------------------------------

## Phase 6 --- Streaming Engine

**Goal:** Build a flexible streaming system that connects content
modules to Kinetiq's native playback engine.

-   [ ] Implement HTTP streaming support
-   [ ] Support HLS streams
-   [ ] Support direct MP4 playback
-   [ ] Implement adaptive streaming quality
-   [ ] Add manual quality selection
-   [ ] Support external subtitle sources
-   [ ] Support required request headers and sessions
-   [ ] Implement stream validation
-   [ ] Add server selection
-   [ ] Implement playback failover
-   [ ] Improve network error recovery
-   [ ] Add caching where appropriate
-   [ ] Implement playback diagnostics

**Architecture principle:** Modules resolve and provide content. Kinetiq
handles native playback.

------------------------------------------------------------------------

## Phase 7 --- Manga & Image Reader

**Goal:** Introduce a complete manga and image reading experience.

### Library & Discovery

-   [ ] Create a dedicated manga library
-   [ ] Integrate manga discovery
-   [ ] Implement manga detail pages
-   [ ] Support chapters and chapter lists
-   [ ] Display reading progress

### Reader

-   [ ] Build a dedicated image reader
-   [ ] Support vertical scrolling
-   [ ] Support horizontal page navigation
-   [ ] Implement right-to-left reading
-   [ ] Add zoom and image scaling
-   [ ] Implement page navigation
-   [ ] Remember reading position
-   [ ] Add bookmarks
-   [ ] Support offline reading
-   [ ] Integrate compatible image modules

------------------------------------------------------------------------

## Phase 8 --- Music Experience

**Goal:** Expand Kinetiq into a complete music platform.

-   [ ] Build a music library
-   [ ] Support artists and albums
-   [ ] Retrieve music metadata
-   [ ] Implement playback queues
-   [ ] Support playlists
-   [ ] Add shuffle and repeat
-   [ ] Support background audio
-   [ ] Integrate iOS Now Playing
-   [ ] Support Lock Screen controls
-   [ ] Remember playback history
-   [ ] Integrate compatible music modules

------------------------------------------------------------------------

## Phase 9 --- Personal Media Servers

**Goal:** Allow users to access their own media libraries remotely.

-   [ ] Implement server management
-   [ ] Support server authentication
-   [ ] Browse remote media libraries
-   [ ] Support remote playback
-   [ ] Retrieve remote metadata
-   [ ] Display server connection status
-   [ ] Investigate supported discovery protocols
-   [ ] Securely store server credentials
-   [ ] Support standard media server protocols

------------------------------------------------------------------------

## Phase 10 --- Offline, Downloads & Synchronization

**Goal:** Make media accessible across different network conditions and
sessions.

-   [ ] Implement a download manager
-   [ ] Support download queues
-   [ ] Display download progress
-   [ ] Support offline playback
-   [ ] Add storage management
-   [ ] Resume interrupted downloads
-   [ ] Synchronize playback history
-   [ ] Synchronize library information
-   [ ] Investigate iCloud synchronization
-   [ ] Implement backup and restore

------------------------------------------------------------------------

## Phase 11 --- Personalization & Advanced Settings

**Goal:** Give users control over their Kinetiq experience.

-   [ ] Add customizable Home screen sections
-   [ ] Implement theme selection
-   [ ] Add accent color customization
-   [ ] Add playback preferences
-   [ ] Add subtitle preferences
-   [ ] Add language preferences
-   [ ] Allow default quality selection
-   [ ] Allow default module selection
-   [ ] Add privacy settings
-   [ ] Add storage settings
-   [ ] Add diagnostic settings

------------------------------------------------------------------------

## Phase 12 --- Release, Testing & Optimization

**Goal:** Prepare Kinetiq for a stable and reliable release.

### Testing

-   [ ] Expand unit tests
-   [ ] Add integration tests
-   [ ] Test module installation and updates
-   [ ] Test playback on physical devices
-   [ ] Test different media formats
-   [ ] Test network interruptions
-   [ ] Test offline functionality
-   [ ] Test synchronization

### Optimization

-   [ ] Improve startup performance
-   [ ] Optimize memory usage
-   [ ] Improve battery efficiency
-   [ ] Optimize image and video loading
-   [ ] Audit application security
-   [ ] Review accessibility
-   [ ] Improve error reporting

### Release

-   [ ] Establish release versioning
-   [ ] Finalize the update log system
-   [ ] Prepare release documentation
-   [ ] Establish release channels
-   [ ] Complete final quality assurance

------------------------------------------------------------------------

## Development Principles

Kinetiq will follow these principles throughout development:

1.  **Native first:** Prioritize native iOS technologies and APIs.
2.  **Performance:** Avoid unnecessary overhead and prioritize smooth
    operation.
3.  **Privacy:** Keep personal media and user data under the user's
    control.
4.  **Modularity:** Build systems that can be extended without rewriting
    the application.
5.  **Reliability:** Preserve existing functionality when introducing
    new features.
6.  **Security:** Verify external content and packages wherever
    supported.
7.  **Consistency:** Maintain a unified design language across all media
    experiences.
8.  **Independent identity:** Kinetiq is its own application, not a
    rebranded copy of another player.

------------------------------------------------------------------------

## Current Development Status

**Current Phase:** Phase 2 --- Playback & Player Experience

**Next Milestone:** Playback Memory

The immediate priority is persistent playback progress, automatic
resume, and a Continue Watching section on the Home screen.

Future phases will build upon this foundation, with module compatibility
and streaming architecture researched before implementation.

------------------------------------------------------------------------

*Kinetiq --- One platform. Every kind of media.*
