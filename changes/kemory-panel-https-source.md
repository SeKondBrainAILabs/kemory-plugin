### Fixed
- **kemory-panel installs and updates without a GitHub SSH key.** Its marketplace entry now points at the HTTPS clone URL. Claude Code cloned the old `github` source over SSH only, so on a machine with no SSH key for GitHub the install or update stopped with `Permission denied (publickey)`. The kemory plugin itself was not affected.
