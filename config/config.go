package config

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/amarbel-llc/treelint/git"
	"github.com/amarbel-llc/treelint/jujutsu"
	"github.com/amarbel-llc/treelint/walk"
	"github.com/charmbracelet/log"
	"github.com/google/shlex"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

// Config is used to represent the list of configured Formatters.
type Config struct {
	AllowMissingFormatter bool     `mapstructure:"allow-missing-formatter" toml:"allow-missing-formatter,omitempty"`
	CI                    bool     `mapstructure:"ci"                      toml:"-"` // not allowed in config
	ClearCache            bool     `mapstructure:"clear-cache"             toml:"-"` // not allowed in config
	CPUProfile            string   `mapstructure:"cpu-profile"             toml:"cpu-profile,omitempty"`
	Excludes              []string `mapstructure:"excludes"                toml:"excludes,omitempty"`
	FailOnChange          bool     `mapstructure:"fail-on-change"          toml:"fail-on-change,omitempty"`
	Formatters            []string `mapstructure:"formatters"              toml:"formatters,omitempty"`
	NoCache               bool     `mapstructure:"no-cache"                toml:"-"` // not allowed in config
	OnUnmatched           string   `mapstructure:"on-unmatched"            toml:"on-unmatched,omitempty"`
	Quiet                 bool     `mapstructure:"quiet"                   toml:"-"` // not allowed in config
	TreeRoot              string   `mapstructure:"tree-root"               toml:"tree-root,omitempty"`
	TreeRootCmd           string   `mapstructure:"tree-root-cmd"           toml:"tree-root-cmd,omitempty"`
	TreeRootFile          string   `mapstructure:"tree-root-file"          toml:"tree-root-file,omitempty"`
	Verbose               uint8    `mapstructure:"verbose"                 toml:"verbose,omitempty"`
	Walk                  string   `mapstructure:"walk"                    toml:"walk,omitempty"`
	WorkingDirectory      string   `mapstructure:"working-dir"             toml:"-"`
	Stdin                 bool     `mapstructure:"stdin"                   toml:"-"` // not allowed in config

	FormatterConfigs map[string]*Formatter `mapstructure:"formatter" toml:"formatter,omitempty"`

	LinterConfigs map[string]*Linter `mapstructure:"linter" toml:"linter,omitempty"`

	Global struct {
		// Deprecated: Use Excludes
		Excludes []string `mapstructure:"excludes" toml:"excludes,omitempty"`
	} `mapstructure:"global" toml:"global,omitempty"`
}

type Formatter struct {
	// Command is the command to invoke when applying this Formatter.
	Command string `mapstructure:"command" toml:"command"`
	// Options are an optional list of args to be passed to Command.
	Options []string `mapstructure:"options,omitempty" toml:"options,omitempty"`
	// Includes is a list of glob patterns used to determine whether this Formatter should be applied against a path.
	Includes []string `mapstructure:"includes,omitempty" toml:"includes,omitempty"`
	// Excludes is an optional list of glob patterns used to exclude certain files from this Formatter.
	Excludes []string `mapstructure:"excludes,omitempty" toml:"excludes,omitempty"`
	// Indicates the order of precedence when executing this Formatter in a sequence of Formatters.
	Priority int `mapstructure:"priority,omitempty" toml:"priority,omitempty"`
	// Does this formatter violate [rule 1] of the formatter spec?
	// [rule 1]: docs/site/reference/formatter-spec.md#1-files-passed-as-arguments
	NoPositionalArgSupport *bool `mapstructure:"no-positional-arg-support" toml:"no-positional-arg-support"`
	// CheckCommand is an optional native read-only check invocation used by
	// `treelint check` instead of the sandbox-and-diff strategy (RFC 0001 §3).
	CheckCommand string `mapstructure:"check-command,omitempty" toml:"check-command,omitempty"`
	// CheckOptions are the args passed to CheckCommand.
	CheckOptions []string `mapstructure:"check-options,omitempty" toml:"check-options,omitempty"`
	// Sandbox forces sandbox execution in check mode even when a native check
	// command is available (RFC 0001 §3, §6).
	Sandbox bool `mapstructure:"sandbox,omitempty" toml:"sandbox,omitempty"`
}

// Linter represents a tool that inspects files and reports problems, exiting
// non-zero when problems are found. Configured under [linter.<name>]; see
// docs/rfcs/0001-linter-support-and-check-repair-modes.md (RFC 0001 §4).
type Linter struct {
	// Command is the read-only check invocation, run as
	// `command [options] [...files]`. It MUST NOT write to the files and MUST
	// exit non-zero when at least one passed file has a finding.
	Command string `mapstructure:"command" toml:"command"`
	// Options are an optional list of args passed before the file list.
	Options []string `mapstructure:"options,omitempty" toml:"options,omitempty"`
	// Includes is a list of glob patterns selecting files this Linter inspects.
	Includes []string `mapstructure:"includes,omitempty" toml:"includes,omitempty"`
	// Excludes is an optional list of glob patterns excluding files from this Linter.
	Excludes []string `mapstructure:"excludes,omitempty" toml:"excludes,omitempty"`
	// Priority controls execution order within a file's tool sequence; lower runs first.
	Priority int `mapstructure:"priority,omitempty" toml:"priority,omitempty"`
	// NoPositionalArgSupport indicates the tool cannot process multiple files at once.
	NoPositionalArgSupport *bool `mapstructure:"no-positional-arg-support" toml:"no-positional-arg-support"`
	// RepairCommand is an optional autofix invocation used in repair mode. If
	// unset, the linter is a no-op in repair mode (RFC 0001 §4).
	RepairCommand string `mapstructure:"repair-command,omitempty" toml:"repair-command,omitempty"`
	// RepairOptions are the args passed to RepairCommand.
	RepairOptions []string `mapstructure:"repair-options,omitempty" toml:"repair-options,omitempty"`
}

// SetFlags appends our flags to the provided flag set.
// We have a flag matching most entries in Config, taking care to ensure the name matches the field name defined in the
// mapstructure tag.
// We rely on a flag's default value being provided in the event the same value was not specified in the config file.
func SetFlags(fs *pflag.FlagSet) {
	fs.Bool(
		"allow-missing-formatter", false,
		"Do not exit with error if a configured formatter is missing. (env $TREELINT_ALLOW_MISSING_FORMATTER)",
	)
	fs.Bool(
		"ci", false,
		"Runs treelint in a CI mode, enabling --no-cache, --fail-on-change and adjusting some other settings "+
			"best suited to a CI use case. (env $TREELINT_CI)",
	)
	fs.BoolP(
		"clear-cache", "c", false,
		"Reset the evaluation cache. Use in case the cache is not precise enough. (env $TREELINT_CLEAR_CACHE)",
	)
	fs.String(
		"cpu-profile", "",
		"The file into which a cpu profile will be written. (env $TREELINT_CPU_PROFILE)",
	)
	fs.StringSlice(
		"excludes", nil,
		"Exclude files or directories matching the specified globs. (env $TREELINT_EXCLUDES)",
	)
	fs.Bool(
		"fail-on-change", false,
		"Exit with error if any changes were made. Useful for CI. (env $TREELINT_FAIL_ON_CHANGE)",
	)
	fs.StringSliceP(
		"formatters", "f", nil,
		"Specify formatters to apply. Defaults to all configured formatters. (env $TREELINT_FORMATTERS)",
	)
	fs.Bool(
		"no-cache", false,
		"Ignore the evaluation cache entirely. Useful for CI. (env $TREELINT_NO_CACHE)",
	)
	fs.StringP(
		"on-unmatched", "u", "info",
		"Log paths that did not match any formatters at the specified log level. Possible values are "+
			"<debug|info|warn|error|fatal>. (env $TREELINT_ON_UNMATCHED)",
	)
	fs.Bool(
		"stdin", false,
		"Format the context passed in via stdin.",
	)
	fs.String(
		"tree-root", "",
		"The root directory from which treelint will start walking the filesystem. "+
			"Defaults to the root of the current git or jujutsu worktree. If not in a git or jujutsu repo, defaults to the "+
			"directory containing the config file. (env $TREELINT_TREE_ROOT)",
	)
	fs.String(
		"tree-root-cmd", "",
		"Command to run to find the tree root. It is parsed using shlex, to allow quoting arguments that "+
			"contain whitespace. If you wish to pass arguments containing quotes, you should use nested quotes "+
			"e.g. \"'\" or '\"'. (env $TREELINT_TREE_ROOT_CMD)",
	)
	fs.String(
		"tree-root-file", "",
		"File to search for to find the tree root. (env $TREELINT_TREE_ROOT_FILE)",
	)
	fs.CountP(
		"verbose", "v",
		"Set the verbosity of logs e.g. -vv. (env $TREELINT_VERBOSE)",
	)
	fs.BoolP(
		"quiet", "q", false, "Disable all logs except errors. (env $TREELINT_QUIET)",
	)
	fs.String(
		"walk", "auto",
		"The method used to traverse the files within the tree root. Currently supports "+
			"<auto|git|jujutsu|filesystem>. (env $TREELINT_WALK)",
	)
	fs.StringP(
		"working-dir", "C", ".",
		"Run as if treelint was started in the specified working directory instead of the current working "+
			"directory. (env $TREELINT_WORKING_DIR)",
	)
}

// NewViper creates a Viper instance pre-configured with the following options:
// * TOML config type
// * automatic env enabled
// * `TREELINT_` env prefix for environment variables
// * replacement of `-` and `.` with `_` when mapping flags to env e.g. `global.excludes` => `TREELINT_GLOBAL_EXCLUDES`.
func NewViper() (*viper.Viper, error) {
	v := viper.New()

	// Enforce toml (may open this up to other formats in the future)
	v.SetConfigType("toml")

	// Allow env overrides for config and flags.
	v.SetEnvPrefix("treelint")
	v.AutomaticEnv()
	v.SetEnvKeyReplacer(strings.NewReplacer("-", "_", ".", "_"))

	// unset some env variables that we don't want automatically applied
	if err := os.Unsetenv("TREELINT_STDIN"); err != nil {
		return nil, fmt.Errorf("failed to unset TREELINT_STDIN: %w", err)
	}

	return v, nil
}

// FromViper takes a viper instance and produces a Config instance.
func FromViper(v *viper.Viper) (*Config, error) {
	logger := log.WithPrefix("config")

	configReset := map[string]any{
		"ci":          false,
		"clear-cache": false,
		"no-cache":    false,
		"stdin":       false,
		"working-dir": ".",
	}

	// reset certain values which are not allowed to be specified in the config file
	if err := v.MergeConfigMap(configReset); err != nil {
		return nil, fmt.Errorf("failed to overwrite config values: %w", err)
	}

	// read config from viper
	var err error

	cfg := &Config{}

	if err = v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// resolve the working directory to an absolute path
	cfg.WorkingDirectory, err = filepath.Abs(cfg.WorkingDirectory)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute path for working directory: %w", err)
	}

	// if the stdin flag was passed, we force the stdin walk type
	if cfg.Stdin {
		cfg.Walk = walk.Stdin.String()
	}

	// determine tree root
	if err = determineTreeRoot(v, cfg, logger); err != nil {
		return nil, fmt.Errorf("failed to determine tree root: %w", err)
	}

	// prefer top level excludes, falling back to global.excludes for backwards compatibility
	if len(cfg.Excludes) == 0 {
		cfg.Excludes = cfg.Global.Excludes
	}

	// validate formatter names do not contain invalid characters
	nameRegex := regexp.MustCompile("^[a-zA-Z0-9_-]+$")

	for name := range cfg.FormatterConfigs {
		if !nameRegex.MatchString(name) {
			return nil, fmt.Errorf(
				"formatter name %q is invalid, must be of the form %s",
				name, nameRegex.String(),
			)
		}
	}

	// validate linter names do not contain invalid characters (RFC 0001 §4)
	for name := range cfg.LinterConfigs {
		if !nameRegex.MatchString(name) {
			return nil, fmt.Errorf(
				"linter name %q is invalid, must be of the form %s",
				name, nameRegex.String(),
			)
		}
	}

	// filter formatters based on provided names
	if len(cfg.Formatters) > 0 {
		filtered := make(map[string]*Formatter)

		// check if the provided names exist in the config
		for _, name := range cfg.Formatters {
			if !nameRegex.MatchString(name) {
				return nil, fmt.Errorf(
					"formatter name %q is invalid, must be of the form %s",
					name, nameRegex.String(),
				)
			}

			formatterCfg, ok := cfg.FormatterConfigs[name]
			if !ok {
				return nil, fmt.Errorf("formatter %v not found in config", name)
			}

			filtered[name] = formatterCfg
		}

		// updated formatters
		cfg.FormatterConfigs = filtered
	}

	// ci mode
	if cfg.CI {
		cfg.NoCache = true
		cfg.FailOnChange = true

		// ensure at least info level logging
		if cfg.Verbose < 1 {
			cfg.Verbose = 1
		}
	}

	return cfg, nil
}

func determineTreeRoot(v *viper.Viper, cfg *Config, logger *log.Logger) error {
	var err error

	// enforce the various tree root options are mutually exclusive
	// some of this is being done for us at the flag level, but you can also set these values in config or environment
	// variables.
	count := 0

	if cfg.TreeRoot != "" {
		count++
	}

	if cfg.TreeRootCmd != "" {
		count++
	}

	if cfg.TreeRootFile != "" {
		count++
	}

	if count > 1 {
		return errors.New("at most one of tree-root, tree-root-cmd or tree-root-file can be specified")
	}

	switch {
	case cfg.TreeRoot != "":
		logger.Infof("tree root specified explicitly: %s", cfg.TreeRoot)

	case cfg.TreeRootFile != "":
		logger.Infof("searching for tree root using tree-root-file: %s", cfg.TreeRootFile)

		_, cfg.TreeRoot, err = FindUp(cfg.WorkingDirectory, cfg.TreeRootFile)
		if err != nil {
			return fmt.Errorf("failed to find tree-root based on tree-root-file: %w", err)
		}

	case cfg.TreeRootCmd != "":
		logger.Infof("searching for tree root using tree-root-cmd: %s", cfg.TreeRootCmd)

		if cfg.TreeRoot, err = execTreeRootCmd(cfg.TreeRootCmd, cfg.WorkingDirectory); err != nil {
			return err
		}

	default:
		// no tree root was specified
		logger.Infof("no tree root specified")

		// attempt to resolve with git
		if cfg.Walk == walk.Auto.String() || cfg.Walk == walk.Git.String() {
			logger.Infof("attempting to resolve tree root using git: %s", git.TreeRootCmd)

			// attempt to resolve the tree root with git
			cfg.TreeRoot, err = execTreeRootCmd(git.TreeRootCmd, cfg.WorkingDirectory)
			if err != nil && cfg.Walk == walk.Git.String() {
				return fmt.Errorf("failed to resolve tree root with git: %w", err)
			}

			if err != nil {
				logger.Infof("failed to resolve tree root with git: %v", err)
			}
		}

		// attempt to resolve with jujutsu
		if cfg.TreeRoot == "" && (cfg.Walk == walk.Auto.String() || cfg.Walk == walk.Jujutsu.String()) {
			logger.Infof("attempting to resolve tree root using jujutsu: %s", jujutsu.TreeRootCmd)

			// attempt to resolve the tree root with jujutsu
			cfg.TreeRoot, err = execTreeRootCmd(jujutsu.TreeRootCmd, cfg.WorkingDirectory)
			if err != nil && cfg.Walk == walk.Git.String() {
				return fmt.Errorf("failed to resolve tree root with jujutsu: %w", err)
			}

			if err != nil {
				logger.Infof("failed to resolve tree root with jujutsu: %v", err)
			}
		}

		if cfg.TreeRoot == "" {
			// fallback to the directory containing the config file
			logger.Infof(
				"setting tree root to the directory containing the config file: %s",
				v.ConfigFileUsed(),
			)

			cfg.TreeRoot = filepath.Dir(v.ConfigFileUsed())
		}
	}

	// resolve tree root to an absolute path
	if cfg.TreeRoot, err = filepath.Abs(cfg.TreeRoot); err != nil {
		return fmt.Errorf("failed to get absolute path for tree root: %w", err)
	}

	logger.Infof("tree root: %s", cfg.TreeRoot)

	return nil
}

func execTreeRootCmd(treeRootCmd string, workingDir string) (string, error) {
	// split the command first, resolving any '' and "" entries
	parts, splitErr := shlex.Split(treeRootCmd)
	if splitErr != nil {
		return "", fmt.Errorf("failed to parse tree-root-cmd: %w", splitErr)
	}

	// set a reasonable timeout of 2 seconds to wait for the command to return
	// it shouldn't take anywhere near this amount of time unless there's a problem
	executionTimeout := 2 * time.Second

	ctx, cancel := context.WithTimeout(context.Background(), executionTimeout)
	defer cancel()

	// construct the command, setting the correct working directory
	//nolint:gosec
	cmd := exec.CommandContext(ctx, parts[0], parts[1:]...)
	cmd.Dir = workingDir

	// setup some pipes to capture stdout and stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stdout pipe for tree-root-cmd: %w", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stderr pipe for tree-root-cmd: %w", err)
	}

	// start processing stderr before we begin executing the command
	go func() {
		// capture stderr line by line and log
		l := log.WithPrefix("tree-root-cmd | stderr")

		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			l.Debugf("%s", scanner.Text())
		}
	}()

	// start executing without waiting
	if cmdErr := cmd.Start(); cmdErr != nil {
		return "", fmt.Errorf("failed to start tree-root-cmd: %w", cmdErr)
	}

	// read stdout until it is closed (command exits)
	output, err := io.ReadAll(stdout)
	if err != nil {
		return "", fmt.Errorf("failed to read stdout from tree-root-cmd: %w", err)
	}

	log.WithPrefix("tree-root-cmd | stdout").Debugf("%s", output)

	// check execution error
	if cmdErr := cmd.Wait(); cmdErr != nil {
		var exitErr *exec.ExitError

		// by experimenting, I noticed that sometimes we received the deadline exceeded error first, other times
		// the exit error indicating the process was killed, therefore, we look for both
		tookTooLong := errors.Is(cmdErr, context.DeadlineExceeded)
		tookTooLong = tookTooLong || (errors.As(cmdErr, &exitErr) && exitErr.String() == "signal: killed")

		if tookTooLong {
			return "", fmt.Errorf(
				"tree-root-cmd was killed after taking more than %v to execute",
				executionTimeout,
			)
		}

		// otherwise, some other kind of error occurred
		return "", fmt.Errorf("failed to execute tree-root-cmd: %w", cmdErr)
	}

	// validate the output
	outputStr := string(output)

	lines := strings.Split(outputStr, "\n")
	nonEmptyLines := slices.DeleteFunc(lines, func(line string) bool {
		return line == ""
	})

	switch len(nonEmptyLines) {
	case 1:
		// return the first line as the tree root
		return nonEmptyLines[0], nil

	case 0:
		// no output was received on stdout
		return "", fmt.Errorf("empty output received after executing tree-root-cmd: %s", treeRootCmd)

	default:
		// multiple lines received on stdout, dump the output to make it clear what happened and throw an error
		log.WithPrefix("tree-root-cmd | stdout").Errorf("\n%s", outputStr)

		return "", fmt.Errorf("tree-root-cmd cannot output multiple lines: %s", treeRootCmd)
	}
}

func Find(searchDir string, fileNames ...string) (path string, err error) {
	for _, f := range fileNames {
		path := filepath.Join(searchDir, f)
		if fileExists(path) {
			return path, nil
		}
	}

	return "", fmt.Errorf("could not find %s in %s", fileNames, searchDir)
}

func FindUp(searchDir string, fileNames ...string) (path string, dir string, err error) {
	for _, dir := range eachDir(searchDir) {
		path, err := Find(dir, fileNames...)
		if err == nil {
			return path, dir, nil
		}
	}

	return "", "", fmt.Errorf("could not find %s in %s", fileNames, searchDir)
}

func eachDir(path string) (paths []string) {
	path, err := filepath.Abs(path)
	if err != nil {
		return
	}

	paths = []string{path}

	if path == "/" {
		return
	}

	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == os.PathSeparator {
			path = path[:i]
			if path == "" {
				path = "/"
			}

			paths = append(paths, path)
		}
	}

	return
}

func fileExists(path string) bool {
	// Some broken filesystems like SSHFS return file information on stat() but
	// then cannot open the file. So we use os.Open.
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()

	// Next, check that the file is a regular file.
	fi, err := f.Stat()
	if err != nil {
		return false
	}

	return fi.Mode().IsRegular()
}
