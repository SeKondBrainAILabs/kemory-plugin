### Changed
- **`kemory-plus` moved to its own repository,
  [kemory-plus](https://github.com/SeKondBrainAILabs/kemory-plus).** The
  kemory marketplace still lists it, so `/plugin install kemory-plus@kemory`
  works as before. Nothing here ships a module or an approval hook any more,
  and `kemory-plus` releases on its own schedule (0.13.0 makes idle memory
  suggestions opt-in with `KEMORY_AUTO_SUGGEST=1`).
