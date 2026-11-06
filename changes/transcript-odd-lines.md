### Fixed
- **Session capture and the store reminder skip a transcript line of unexpected shape.** A line that is valid JSON but not a message object (such as `null`, a number or a list) used to stop both for the whole session; now only that line is ignored.
