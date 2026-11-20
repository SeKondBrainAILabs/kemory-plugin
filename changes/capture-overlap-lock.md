### Fixed
- **Overlapping capture runs for one session no longer store the same turns twice.** A Stop capture still uploading when SessionEnd or an auto PreCompact started used to produce a duplicate memory; the second run now waits for the first and stores only turns it did not.
