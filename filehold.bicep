@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the VM')
param vmName string = 'vm-filehold'

@description('Admin username for the VM')
param adminUsername string

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('VM size.')
param vmSize string = 'Standard_D4s_v3'

@description('Name of the existing virtual network')
param vnetName string = 'vnet-fileshares-azusc'

@description('Name of the existing subnet')
param subnetName string = 'snet-filehold'

@description('Windows Server and SQL image offer')
@allowed([
  'sql2017-ws2019'
])
param imageOffer string = 'sql2017-ws2019'

@description('SQL Server SKU (Standard/Enterprise/Web for sql2017-ws2019)')
@allowed([
  'standard'
  'enterprise'
  'web'
])
param sqlSku string = 'standard'

var nicName = '${vmName}-nic'
var nsgName = '${subnetName}-nsg'

//
// Existing VNet + Subnet
//
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: subnetName
  parent: vnet
}

//
// NSG – only allow in/out from VirtualNetwork (includes peered VNets)
//
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      // INBOUND
      {
        name: 'Allow_VNet_Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny_All_Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }

      // OUTBOUND
      {
        name: 'Allow_VNet_Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Deny_All_Outbound'
        properties: {
          priority: 200
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
// Attach NSG to existing subnet WITHOUT touching addressPrefix, delegations, etc.
//
module attachNsg 'update-subnet.bicep' = {
  name: 'update-vnet-subnet-${vnetName}-${subnetName}'
  params: {
    vnetName: vnetName
    subnetName: subnetName
    // Take existing subnet properties and just add networkSecurityGroup
    properties: union(subnet.properties, {
      networkSecurityGroup: {
        id: nsg.id
      }
    })
  }
}

//
// NIC (no public IP – only reachable from peered networks / VPN / Bastion)
//
resource nic 'Microsoft.Network/networkInterfaces@2022-01-01' = {
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
  }
}

//
// VM – Windows Server 2019 + SQL Server 2017
//
resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: imageOffer      // sql2017-ws2019
        sku: sqlSku            // standard | enterprise | web
        version: 'latest'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
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
  dependsOn: [
    attachNsg
  ]
}

output vmNameOut string = vm.name
output subnetNsgId string = nsg.id
