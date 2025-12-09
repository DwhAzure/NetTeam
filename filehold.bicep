@description('Location for all resources')
param location string = resourceGroup().location

@description('Admin username for the local administrator account on the VM')
param adminUsername string

@secure()
@description('Admin password for the local administrator account on the VM')
param adminPassword string

@description('Size of the VM')
param vmSize string = 'Standard_D4s_v5'

@description('Existing VNet name')
param vnetName string = 'vnet-fileshares-azusc'

@description('Existing subnet name for DFS server')
param subnetName string = 'snet-dfs-server'

var vmName = 'vm-dfs-01'
var nicName = 'nic-${vmName}'
var nsgName = 'nsg-dfs-server'

//
// EXISTING VNET / SUBNET - we DO NOT create them
//
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' existing = {
  name: subnetName
  parent: vnet
}

//
// NSG with only VNet/peered-VNet allowed, no Internet outbound
//
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      // Inbound: allow only from VNet (includes peered VNets)
      {
        name: 'allow-vnet-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      // Inbound: deny everything else
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }

      // Outbound: allow VNet only (includes peered VNets)
      {
        name: 'allow-vnet-outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      // Outbound: explicitly deny Internet
      {
        name: 'deny-internet-outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Internet'
        }
      }
      // Outbound: final deny-all sweeper
      {
        name: 'deny-all-outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

//
// NIC (no public IP) with NSG attached and existing subnet
//
resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: nicName
  location: location
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
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

//
// VM: Windows Server 2022
//
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

//
// VM extension to install DFS roles
//
resource vmDfsExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'InstallDFS'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Install-WindowsFeature FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools"'
    }
  }
}
