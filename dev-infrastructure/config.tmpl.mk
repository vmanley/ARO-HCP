REGION ?= {{ .region }}
SVC_RESOURCEGROUP ?= {{ .serviceClusterRG }}
MGMT_RESOURCEGROUP ?= {{ .managementClusterRG }}
REGIONAL_RESOURCEGROUP ?= {{ .regionRG }}
SVC_KV_RESOURCEGROUP ?= {{ .serviceKeyVaultRG }}
GLOBAL_RESOURCEGROUP ?= {{ .globalRG }}
IMAGE_SYNC_RESOURCEGROUP ?= {{ .imageSyncRG }}
IMAGE_SYNC_ENVIRONMENT ?= {{ .imageSyncEnvironmentName }}
ARO_HCP_IMAGE_ACR ?= {{ .svcAcrName }}
REPOSITORIES_TO_SYNC ?= '{{ .imageSyncRepositories }}'
AKS_NAME ?= {{ .aksName }}
CS_PG_NAME ?= {{ .clusterServicePostgresName }}
MAESTRO_PG_NAME ?= {{ .maestroPostgresName }}
