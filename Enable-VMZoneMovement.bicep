targetScope = 'resourceGroup'

@description('Name of the virtual machine to create.')
param vmName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Availability zone for the virtual machine.')
@allowed([
  '1'
  '2'
  '3'
])
param availabilityZone string = '1'

@description('Virtual machine size.')
param vmSize string = 'Standard_D2s_v5'

@description('Administrator username for the virtual machine.')
param adminUsername string = 'azureuser'

@secure()
@description('SSH public key used to authenticate the administrator account.')
param adminSshPublicKey string

@description('Virtual network address space.')
param vnetAddressPrefix string = '10.42.0.0/16'

@description('Subnet address prefix.')
param subnetAddressPrefix string = '10.42.0.0/24'

@description('Additional tags applied to the virtual machine and network resources.')
param tags object = {}

var vnetName = '${vmName}-vnet'
var subnetName = 'default'
var nsgName = '${vmName}-nsg'
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'
var requiredTags = union(tags, {
  useNRPDeallocateOnFabricFailure: 'true'
})

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' = {
  name: vmName
  location: location
  zones: [
    availabilityZone
  ]
  tags: requiredTags
  identity: {
    type: 'SystemAssigned'
  }
  // The private-preview property is supported by ARM but is not yet present in Bicep's type metadata.
  properties: any({
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Premium_ZRS'
        }
      }
      dataDisks: []
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    resiliencyProfile: {
      zoneMovement: {
        isEnabled: true
      }
    }
  })
}

output virtualMachineId string = vm.id
output virtualMachineName string = vm.name
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output availabilityZone string = availabilityZone
output zoneMovementEnabled bool = true
