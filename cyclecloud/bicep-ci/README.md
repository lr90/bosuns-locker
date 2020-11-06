# CycleCloud install using Bicep + Cloud-Init
With CycleCloud 8 now supporting Cloud-Init as a means of configuring VMs it seemed appropriate to look at using cloud-init in the deployment of CycleCloud itself

This exemplar uses [Bicep](https://github.com/Azure/bicep) to deploy the Azure resource and has been tested with v0.1.226-alpha. Much like Terraform, Bicep drastically simplifies the authoring experience and provides a transparent abastraction over ARM.

Deployment steps
```
bicep build sub.bicep cyclecloud.bicep
az deployment sub create --template-file sub.json --location uksouth
az deployment group create --resource-group rg-bicep --template-file cyclecloud.json
```
