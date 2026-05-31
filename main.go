package main

import (
	"os"

	"github.com/amarbel-llc/treelint/cmd"
)

// version and commit are injected at build time. The amarbel-llc/nixpkgs fork's
// buildGoApplication sets -X main.version (from version.env) and -X main.commit
// (from the flake's self.rev); a plain `go build` leaves the defaults below.
// See eng-versioning(7).
var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	// todo how are exit codes thrown by commands?
	root, _ := cmd.NewRoot(version, commit)
	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
