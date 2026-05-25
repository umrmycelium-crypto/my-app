param location string = 'southcentralus'
param rgName string = 'vision-platform-rg'
param postgresAdmin string = 'pgadmin'
@secure()
param postgresPassword string = 'REPLACE_WITH_STRONG_PASSWORD'

resource storage 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: toLower('vblob${uniqueString(subscription().id, resourceGroup().id)}')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2021-06-01' = {
  name: 'vision-pg-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    version: '13'
    administratorLogin: postgresAdmin
    administratorLoginPassword: postgresPassword
    storage: {
      storageSizeGB: 128
    }
  }
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
}

resource redis 'Microsoft.Cache/Redis@2021-06-01' = {
  name: 'vision-redis-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1
    }
  }
}

output storageAccountName string = storage.name
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output redisHost string = redis.properties.hostName
