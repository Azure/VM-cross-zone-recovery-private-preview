# Enable cross zone recovery for VMs (preview)

Virtual machines can be recovered quickly from zonal outages by moving them across availability zones. This solution guarantees a Recovery Point Objective (RPO) of zero and a Recovery Time Objective (RTO) of ~15 minutes. By using [zone redundant disks](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-redundancy#zone-redundant-storage-for-managed-disks) we will are able to provide an RPO of 0. As the feature is dependent on zone redundant disks all its [limitation](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-redundancy#limitations) will apply to the recovery solution also.

## Sign up for preview

Sign-up for the preview via this [form](https://aka.ms/ZRVMPreview).
You will receive an email notification once you are enrolled for the preview.

## Provide feedback 
Please fill up this [feedback form](https://aka.ms/ZRVMFeedback-form) as you try out the preview. This will help us determine the pain points that can be overcome as we launch the next releases.

## Unsupported VM configurations
- VM that are not pinned to an availability zone.
- Not supported VMs using [locally redundant disks](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-redundancy#locally-redundant-storage-for-managed-disks). as OS/Data disks.
- Public IP that are regional/have availability zone as “No Zone”
- Public IP with SKU as Basic.
- Private IP that are static. 

## Get started
In this preview customers will be able to move the existing/new virtual machine that meet the prerequisites across availability zone. 

## Prerequisites
- VM must be deployed to a specific availability zone. 
- Ensure that the VM has the tag “EnableAvailabilityZoneUpdate: true”. The tag is crucial as you will not be able to move the VM across zones without this tag on the virtual machine.
- Zone redundant disks data disks (premium/standard) must be used.
- Zone redundant OS disks (premium/standard) or Ephemeral OS disk must be used.
- Dynamic Private IP must be used.
- Public IP SKU should be standard.
- Load Balancer and Gateway should be of standard SKU.

### Create a VM
Please follow the below steps in order. For this example, a new VM is created. The feature will work for an existing VM please follow the from step 5 onwards if using existing VM. Ensure that the prerequisites are met for the existing VM. 

1.	Create a VM in the subscription you have signed up for this preview.
2.	Ensure the VM has an availability options set as Availability zone and zone options as self-selected zone. Choose an availability zone (1/2/3) as per your choice.
   
   ![Screenshot1](./images/2-Availability-zone-selection.png)  
   
3.	In disks tab, select the OS and data disks as zone redundant storage as below -

  	![Screenshot2](./images/os-disk-type-zrs.png)
  	
4. If you are using OS disk type as locally redundant storage (LRS) disks you can migrate them to zone redundant storage (ZRS) disks. Please see the documentation here. 
5.	In networking tab, please provide the details as you normally would. You can choose to have a public IP if needed for testing this feature.   
6.	Create a tag `EnableAvailabilityZoneUpdate: true` as below on virtual machine resource – 

  	![Screenshot3](./images/VM-tag-value.png)
  	
7.	Review and create the VM successfully along with the tag. For existing VM ensure that the tag is added.

## Changing zone of VM
1.	Open the Cloud shell (PowerShell) from portal. Direct link -> https://shell.azure.com/ 
2.	Uploading the script that orchestrates moving the VM across zones. 
   a.	Upload the script [Change-VMZone.ps1](./Change-VMZone.ps1) to cloud shell by navigating to Manage files -> Upload.
  	
      ![Screenshot4](./images/upload-script.png)
  	
   b.	Optionally you can copy the scripts content on a new file using editors.
4.	Note the availability zone and the IP address (Public and Private) of the VM you are testing.
5.	To move the VM across zone issue the below command on the CloudShell interface from portal.
   
   `.\Change-VMZone.ps1 -subscriptionId {subscriptionId} -resourceGroupName {resourceGroupName} -vmName {vmName} -targetZone {1 or 2 or 3} -newNetworkResourceId {networkResourceId}`

| Parameter | Description |
| --- | --- |
|SubscriptionId | Virtual machine subscription ID.|
|ResourceGroupName|Virtual machine resource group.|
|vmName|Virtual machine name.|
|targetZone|New availability zone for virtual machine.|
|(Optional) newNetworkResourceId|Resource ID for new network interface card to be attached to recovered virtual machine.|

5.	Expected behaviour – 
Refresh the overview blade in the portal for the virtual machine, you would see the VM state change from running to deallocating to deallocated. Within few minutes the VM state will be set to running and the availability zone would be the targetZone provided in the command.
Optionally if you have provided a new network interface id the same ranges will be used to assign the IP address of the recovered VM.
6.	Please fill up this [feedback form](https://aka.ms/ZRVMFeedback-form). 


  	
