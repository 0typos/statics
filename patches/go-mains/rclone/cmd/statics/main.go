// A trimmed rclone for the statics extra archive: the backends and commands
// below instead of rclone.go's backend/all and cmd/all, which are three times
// the size. Copied into rclone's source tree at build time, so rclone's own
// go.mod and go.sum apply. docs/TOOLKIT.md lists what is left out.
package main

import (
	"github.com/rclone/rclone/cmd"

	_ "github.com/rclone/rclone/backend/http"
	_ "github.com/rclone/rclone/backend/local"
	_ "github.com/rclone/rclone/backend/s3"
	_ "github.com/rclone/rclone/backend/sftp"
	_ "github.com/rclone/rclone/backend/webdav"

	_ "github.com/rclone/rclone/cmd/cat"
	_ "github.com/rclone/rclone/cmd/check"
	_ "github.com/rclone/rclone/cmd/config"
	_ "github.com/rclone/rclone/cmd/copy"
	_ "github.com/rclone/rclone/cmd/copyto"
	_ "github.com/rclone/rclone/cmd/ls"
	_ "github.com/rclone/rclone/cmd/lsd"
	_ "github.com/rclone/rclone/cmd/lsf"
	_ "github.com/rclone/rclone/cmd/rcat"
	_ "github.com/rclone/rclone/cmd/size"
	_ "github.com/rclone/rclone/cmd/sync"
	_ "github.com/rclone/rclone/cmd/version"
)

func main() {
	cmd.Main()
}
