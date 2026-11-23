### Fixed
- **Passwords and keys assigned with `=>` are redacted.** A PHP array (`'password' => '...'`), a Ruby hash (`:api_key => "..."`, `{"token"=>"..."}`) or a Perl fat comma used to send its value off the machine in clear. A JavaScript arrow function whose parameter is named like a credential (`token => token.trim()`) is now redacted too.
