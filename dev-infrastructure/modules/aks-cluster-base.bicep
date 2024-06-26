// Constants
param aksClusterName string = take('aro-hcp-${clusterType}-${uniqueString(clusterType)}', 63)
param aksNodeResourceGroupName string

// System agentpool spec(Infra)
param systemAgentMinCount int = 2
param systemAgentMaxCount int = 3
param systemAgentVMSize string = 'Standard_D2s_v3'

// User agentpool spec (Worker)
param deployUserAgentPool bool = false
param userAgentMinCount int = 2
param userAgentMaxCount int = 3
param userAgentVMSize string = 'Standard_D2s_v3'

param serviceCidr string = '10.130.0.0/16'
param dnsServiceIP string = '10.130.0.10'

// Passed Params and Overrides
param location string

@description('Set to true to prevent resources from being pruned after 48 hours')
param persist bool = false

param currentUserId string
param enablePrivateCluster bool = true
param kubernetesVersion string
param istioVersion string
param vnetAddressPrefix string
param subnetPrefix string
param podSubnetPrefix string
param clusterType string
param workloadIdentities array

@maxLength(24)
param aksKeyVaultName string

// Local Params
@description('Optional DNS prefix to use with hosted Kubernetes API server FQDN.')
param dnsPrefix string = aksClusterName

@description('Disk size (in GB) to provision for each of the agent pool nodes. This value ranges from 0 to 1023. Specifying 0 will apply the default disk size for that agentVMSize.')
@minValue(0)
@maxValue(1023)
param systemOsDiskSizeGB int = 32
param userOsDiskSizeGB int = 32

@description('Perform cryptographic operations using keys. Only works for key vaults that use the Azure role-based access control permission model.')
var keyVaultCryptoUserId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '12338af0-0e69-4776-bea7-57ae8d297424'
)

var aksClusterAdminRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions/',
  '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'
)
var networkContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions/',
  '4d97b98b-1d4f-4787-a291-c67834d212e7'
)

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

// Main
// Tags the subscription
resource subscriptionTags 'Microsoft.Resources/tags@2024-03-01' = {
  name: 'default'
  properties: {
    tags: {
      persist: toLower(string(persist))
      deployedBy: currentUserId
    }
  }
}

resource aks_keyvault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  location: location
  name: aksKeyVaultName
  tags: {
    resourceGroup: resourceGroup().name
  }
  properties: {
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        {
          // TODO: restrict in higher environments
          value: '0.0.0.0/0'
        }
      ]
    }
    // TODO: disabled in higher environments
    publicNetworkAccess: 'Enabled'
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
  }
}

resource aks_etcd_kms 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: aks_keyvault
  name: 'aks-etcd-encryption'
  properties: {
    kty: 'RSA'
    keyOps: [
      'encrypt'
      'decrypt'
    ]
    keySize: 2048
    rotationPolicy: {
      lifetimeActions: [
        {
          action: {
            type: 'notify'
          }
          trigger: {
            timeBeforeExpiry: 'P30D'
          }
        }
      ]
    }
  }
}

resource aks_keyvault_crypto_user 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksClusterUserDefinedManagedIdentity.id, keyVaultCryptoUserId, aks_keyvault.id)
  scope: aks_keyvault
  properties: {
    roleDefinitionId: keyVaultCryptoUserId
    principalId: aksClusterUserDefinedManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  location: location
  name: 'aks-net'
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource aksNodeSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'ClusterSubnet-001'
  properties: {
    addressPrefix: subnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    serviceEndpoints: [
      {
        service: 'Microsoft.AzureCosmosDB'
      }
      {
        service: 'Microsoft.ContainerRegistry'
      }
      {
        service: 'Microsoft.Storage'
      }
      {
        service: 'Microsoft.KeyVault'
      }
    ]
  }
}

resource aksPodSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'PodSubnet-001'
  properties: {
    addressPrefix: podSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
    delegations: [
      {
        name: 'AKS'
        properties: {
          serviceName: 'Microsoft.ContainerService/managedClusters'
        }
      }
    ]
  }
  dependsOn: [
    aksNodeSubnet
  ]
}

resource aksClusterUserDefinedManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${aksClusterName}-msi'
  location: location
}

resource aksNetworkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vnet
  name: guid(aksClusterUserDefinedManagedIdentity.id, networkContributorRoleId, aksNodeSubnet.id)
  properties: {
    roleDefinitionId: networkContributorRoleId
    principalId: aksClusterUserDefinedManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aksClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aksCluster
  name: guid(aksClusterUserDefinedManagedIdentity.id, aksClusterAdminRoleId, aksCluster.id)
  properties: {
    roleDefinitionId: aksClusterAdminRoleId
    principalId: aksClusterUserDefinedManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  location: location
  name: aksClusterName
  tags: {
    persist: toLower(string(persist))
    clusterType: clusterType
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksClusterUserDefinedManagedIdentity.id}': {}
    }
  }
  properties: {
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    nodeResourceGroup: aksNodeResourceGroupName
    apiServerAccessProfile: {
      enablePrivateCluster: enablePrivateCluster
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '5m'
          syncSecret: 'true'
        }
      }
    }
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    dnsPrefix: dnsPrefix
    agentPoolProfiles: [
      {
        name: 'system'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        orchestratorVersion: kubernetesVersion
        enableAutoScaling: true
        enableEncryptionAtHost: true
        enableFIPS: true
        osDiskType: 'Ephemeral'
        osDiskSizeGB: systemOsDiskSizeGB
        count: systemAgentMinCount
        minCount: systemAgentMinCount
        maxCount: systemAgentMaxCount
        vmSize: systemAgentVMSize
        vnetSubnetID: aksNodeSubnet.id
        podSubnetID: aksPodSubnet.id
        maxPods: 100
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
      }
    ]
    networkProfile: {
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      networkPlugin: 'azure'
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
    }
    autoScalerProfile: {
      'balance-similar-node-groups': 'false'
      'scan-interval': '10s'
      'scale-down-delay-after-add': '10m'
      'scale-down-delay-after-delete': '20s'
      'scale-down-delay-after-failure': '3m'
      'scale-down-unneeded-time': '10m'
      'scale-down-unready-time': '20m'
      'scale-down-utilization-threshold': '0.5'
      'skip-nodes-with-local-storage': 'false'
      'max-graceful-termination-sec': '600'
      'max-node-provision-time': '15m'
    }
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
      upgradeChannel: 'node-image'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      azureKeyVaultKms: {
        enabled: true
        keyId: aks_etcd_kms.properties.keyUriWithVersion
        keyVaultNetworkAccess: 'Public'
      }
      imageCleaner: {
        enabled: true
        intervalHours: 24
      }
      workloadIdentity: {
        enabled: true
      }
    }
    serviceMeshProfile: {
      mode: 'Istio'
      istio: {
        components: {
          ingressGateways: [
            {
              enabled: true
              mode: 'External'
            }
          ]
        }
        revisions: [
          istioVersion
        ]
      }
    }
  }
}

// additional agent pool for user workload
resource userPool 'Microsoft.ContainerService/managedClusters/agentPools@2024-02-01' = if (deployUserAgentPool) {
  name: 'user'
  parent: aksCluster
  properties: {
    osType: 'Linux'
    osSKU: 'AzureLinux'
    mode: 'User'
    orchestratorVersion: kubernetesVersion
    enableAutoScaling: true
    enableEncryptionAtHost: true
    enableFIPS: true
    osDiskType: 'Ephemeral'
    osDiskSizeGB: userOsDiskSizeGB
    count: userAgentMinCount
    minCount: userAgentMinCount
    maxCount: userAgentMaxCount
    vmSize: userAgentVMSize
    vnetSubnetID: aksNodeSubnet.id
    podSubnetID: aksPodSubnet.id
    maxPods: 250
    availabilityZones: [
      '1'
      '2'
      '3'
    ]
  }
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aksCluster.id, acrPullRoleDefinitionId)
  properties: {
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: acrPullRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [
  for wi in workloadIdentities: {
    location: location
    name: '${wi.value.uamiName}-${location}'
  }
]

resource uami_fedcred 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for i in range(0, length(workloadIdentities)): {
    parent: uami[i]
    name: '${workloadIdentities[i].value.uamiName}-${location}-fedcred'
    properties: {
      audiences: [
        'api://AzureADTokenExchange'
      ]
      issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
      subject: 'system:serviceaccount:${workloadIdentities[i].value.namespace}:${workloadIdentities[i].value.serviceAccountName}'
    }
  }
]

module serviceAccounts './aks-manifest.bicep' = {
  name: '${aksClusterName}-service-accounts'
  params: {
    aksClusterName: aksClusterName
    manifests: [
      for i in range(0, length(workloadIdentities)): {
        apiVersion: 'v1'
        kind: 'ServiceAccount'
        metadata: {
          name: workloadIdentities[i].value.serviceAccountName
          namespace: workloadIdentities[i].value.namespace
          annotations: {
            'azure.workload.identity/client-id': uami[i].properties.clientId
          }
        }
      }
    ]
    aksManagedIdentityId: aksClusterUserDefinedManagedIdentity.id
    location: location
  }
  dependsOn: [
    aksClusterAdminRoleAssignment
  ]
}

// Outputs
output userAssignedIdentities array = [
  for i in range(0, length(workloadIdentities)): {
    uamiID: uami[i].id
    uamiName: workloadIdentities[i].value.uamiName
    uamiClientID: uami[i].properties.clientId
    uamiPrincipalID: uami[i].properties.principalId
  }
]
output aksVnetId string = vnet.id
output aksNodeSubnetId string = aksNodeSubnet.id
output aksOidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output aksClusterName string = aksClusterName
