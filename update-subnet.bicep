@description('Name of the VNet containing the subnet')
param vnetName string

@description('Name of the subnet to update')
param subnetName string

@description('Complete properties object to apply to the subnet')
param properties object

// Get existing vnet
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vnetName
}

// Update the subnet with the provided properties
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' = {
  name: subnetName
  parent: vnet
  properties: properties
}
