package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// newVersionCmd implements the `version` subcommand mandated by
// eng-versioning(7). conformist pins no downstream components, so it emits a
// single self-identification line: "<name> <version>+<commit>".
func newVersionCmd(name, version, commit string) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			_, err := fmt.Fprintf(cmd.OutOrStdout(), "%s %s+%s\n", name, version, commit)

			return err
		},
	}
}
