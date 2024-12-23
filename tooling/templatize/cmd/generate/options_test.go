package generate

import (
	"fmt"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"

	options "github.com/Azure/ARO-HCP/tooling/templatize/cmd"
	"github.com/Azure/ARO-HCP/tooling/templatize/internal/testutil"
)

func TestRawOptions(t *testing.T) {
	tmpdir := t.TempDir()
	opts := &RawGenerationOptions{
		RawOptions: options.RawOptions{
			ConfigFile:  "../../testdata/config.yaml",
			Cloud:       "public",
			DeployEnv:   "dev",
			Region:      "uksouth",
			RegionStamp: "1",
			CXStamp:     "cx",
		},
		Input:  "../../testdata/helm.sh",
		Output: fmt.Sprintf("%s/helm.sh", tmpdir),
	}
	assert.NoError(t, generate(opts))
	testutil.CompareFileWithFixture(t, filepath.Join(tmpdir, "helm.sh"))
}
