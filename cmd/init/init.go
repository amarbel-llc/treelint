package init

import (
	_ "embed"
	"fmt"
	"os"
)

// We embed the sample toml file for use with the init flag.
//
//go:embed init.toml
var initBytes []byte

func Run() error {
	if err := os.WriteFile("conformist.toml", initBytes, 0o600); err != nil {
		return fmt.Errorf("failed to write conformist.toml: %w", err)
	}

	fmt.Printf("Generated conformist.toml. Now it's your turn to edit it.\n")

	return nil
}
